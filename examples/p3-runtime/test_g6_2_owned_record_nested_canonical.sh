#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-nested-canonical.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wat="$repo_root/examples/p3-runtime/g6-2-owned-record-nested-producer-canonical.wat"
wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-nested-producer.wit"
core_wasm="$tmp_dir/canonical.core.wasm"
embedded="$tmp_dir/canonical.embedded.wasm"
component="$tmp_dir/canonical.component.wasm"

test -f "$wit"
test -f "$wat" || {
  printf 'missing canonical nested producer WAT: %s\n' "$wat" >&2
  exit 1
}
test -x "$toolchain_bin"

wit_sha256=$(sha256sum "$wit" | awk '{print $1}')
printf 'wit-sha256=%s\n' "$wit_sha256"
test "$wit_sha256" = \
  9662440709b01044544d4c4350f3e6f783a8f06aaa5c884a96a1e43a935a7543
for marker in \
  '[producer-record-byte-size] 4' \
  '[producer-record-alignment] 4' \
  '[producer-nested-ticket-offset] 0' \
  '[producer-nested-path] inner.ticket' \
  '[producer-stream-capacity] 1' \
  '[producer-source-signature] (i32) -> (i32)' \
  '[producer-input-mode]' \
  '[producer-ownership-mask] guest=1 transferred=2' \
  '[producer-record-transfer]' \
  '[producer-resource-drop-exactly-once]' \
  '[producer-child-before-parent-cleanup]'; do
  grep -Fq ";; $marker" "$wat"
done
if grep -Fq '__arc_' "$wat"; then
  printf 'nested producer canonical WAT contains ARC symbol\n' >&2
  exit 1
fi
if rg -n 'ref\.null|struct\.new|array\.new' "$wat"; then
  printf 'nested producer canonical WAT crosses a Wasm GC reference boundary\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" \
  owned-record-nested-producer -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'G6.2 owned-record nested canonical contract gate passed layout=outer:4 alignment:4 inner.ticket-offset:0 capacity:1 source=(i32)->(i32)\n'
