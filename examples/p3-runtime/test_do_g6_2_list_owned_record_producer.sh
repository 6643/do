#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-list-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-list-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-list-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wat="$tmp_dir/list-owned-record-producer.wat"
wit="$tmp_dir/list-owned-record-producer.wit"
core_wasm="$tmp_dir/list-owned-record-producer.core.wasm"
embedded="$tmp_dir/list-owned-record-producer.embedded.wasm"
component="$tmp_dir/list-owned-record-producer.component.wasm"
stderr="$tmp_dir/build.stderr"

test -x "$do_bin"
test -f "$source"
test -f "$probe_wit"
test -x "$toolchain_bin"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat" \
  >"$tmp_dir/build.stdout" 2>"$stderr"

test -s "$wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  cf7d047069cd9b30066debc88ce8edc159c9d2a90a310e56e384bb42c19cd6eb

grep -Fq 'package do:g6-2-owned-record-list-producer@0.1.0;' "$wit"
grep -Fq 'interface types {' "$wit"
grep -Fq 'record list-entry {' "$wit"
grep -Fq 'values: list<u32>,' "$wit"
grep -Fq 'ticket: own<ticket>,' "$wit"
grep -Fq 'consume-via-stream: async func(' "$wit"
grep -Fq 'data: stream<list-entry>' "$wit"
grep -Fq 'world owned-record-list-producer' "$wit"
grep -Fq 'export produce: async func(mode: u32) -> result<_, error-code>;' "$wit"
if grep -Eq 'do:g6-2-(c-min|batched|dynamic|scalar-list)-producer|stream<resource-entry>' "$wit"; then
  printf 'list-owned-record producer emitted an out-of-scope neighboring shape\n' >&2
  exit 1
fi

for marker in \
  '[producer-record-byte-size] 12' \
  '[producer-record-alignment] 4' \
  '[producer-record-values-pointer-offset] 0' \
  '[producer-record-values-length-offset] 4' \
  '[producer-record-ticket-offset] 8' \
  '[producer-list-stride] 4' \
  '[producer-list-capacity] 3' \
  '[producer-stream-capacity] 1' \
  '[producer-record-transfer]' \
  '[producer-list-release-exactly-once]' \
  '[producer-resource-drop-exactly-once]' \
  '[producer-child-before-parent-cleanup]'; do
  grep -Fq ";; $marker" "$wat"
done
grep -Fq '(func (export "[async-lift]produce")' "$wat"
if grep -Fq '__arc_' "$wat"; then
  printf 'list-owned-record producer emitted an ARC symbol\n' >&2
  exit 1
fi
if grep -Eq '\(ref (null|extern|func|eq|struct|array)' "$wat"; then
  printf 'list-owned-record producer crosses a Wasm GC reference boundary\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-list-producer \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

printf 'G6.2 list-owned-record producer Do Component gate passed record-size=12 list-capacity=3 drops=1\n'
