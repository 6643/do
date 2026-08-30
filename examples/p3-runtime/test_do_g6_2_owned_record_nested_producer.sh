#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
source="$repo_root/examples/p3-runtime/g6-2-owned-record-nested-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-nested-producer.wit"
canonical_wat="$repo_root/examples/p3-runtime/g6-2-owned-record-nested-producer-canonical.wat"
template_wat="$repo_root/src/build/owned_record_nested_stream_producer_template.wat"
tmp_root="$repo_root/.tmp/do-tmp"
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-nested-producer.XXXXXX")
cleanup() {
  if [[ -d "$tmp_dir" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

core_wat="$tmp_dir/owned-record-nested-producer.wat"
wit="$tmp_dir/owned-record-nested-producer.wit"
core_wasm="$tmp_dir/owned-record-nested-producer.core.wasm"
embedded="$tmp_dir/owned-record-nested-producer.embedded.wasm"
component="$tmp_dir/owned-record-nested-producer.component.wasm"

test -x "$do_bin"
test -f "$source"
test -f "$probe_wit"
test -f "$canonical_wat"
test -f "$template_wat"
test -x "$toolchain_bin"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
cmp "$core_wat" "$canonical_wat"
cmp "$core_wat" "$template_wat"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  9662440709b01044544d4c4350f3e6f783a8f06aaa5c884a96a1e43a935a7543

for marker in \
  '[producer-record-byte-size] 4' \
  '[producer-record-alignment] 4' \
  '[producer-nested-ticket-offset] 0' \
  '[producer-nested-path] inner.ticket' \
  '[producer-stream-capacity] 1' \
  '[producer-source-signature] (i32) -> (i32)' \
  '[producer-ownership-mask] guest=1 transferred=2' \
  '[producer-record-transfer]' \
  '[producer-resource-drop-exactly-once]' \
  '[producer-child-before-parent-cleanup]'; do
  grep -Fq ";; $marker" "$core_wat"
done
grep -Fq '(func (export "[async-lift]produce")' "$core_wat"
if grep -Fq '__arc_' "$core_wat"; then
  printf 'owned-record nested producer emitted an ARC symbol\n' >&2
  exit 1
fi
if rg -n 'ref\.null|struct\.new|array\.new' "$core_wat"; then
  printf 'owned-record nested producer crosses a Wasm GC reference boundary\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" \
  owned-record-nested-producer -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'G6.2 owned-record nested producer Do Component gate passed layout=outer:4 alignment:4 inner.ticket-offset:0 capacity:1\n'
