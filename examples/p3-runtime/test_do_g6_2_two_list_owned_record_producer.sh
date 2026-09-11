#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-two-list-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-two-list-producer.wit"
canonical_wat="$repo_root/examples/p3-runtime/g6-2-owned-record-two-list-producer-canonical.wat"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-two-list-owned-record-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wat="$tmp_dir/two-list-owned-record-producer.wat"
wit="$tmp_dir/two-list-owned-record-producer.wit"
core_wasm="$tmp_dir/two-list-owned-record-producer.core.wasm"
embedded="$tmp_dir/two-list-owned-record-producer.embedded.wasm"
component="$tmp_dir/two-list-owned-record-producer.component.wasm"

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$source"
test -f "$probe_wit"
test -f "$canonical_wat"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$wat" \
  >"$tmp_dir/build.stdout" 2>"$tmp_dir/build.stderr"

test -s "$wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  14ba67e070346a127e75c7dfd73c71d6082ad7d9385c7d803834319dabc6404a
cmp "$wat" "$canonical_wat"

grep -Fq 'package do:g6-2-owned-record-two-list-producer@0.1.0;' "$wit"
grep -Fq 'record two-list-entry {' "$wit"
grep -Fq 'first: list<u32>,' "$wit"
grep -Fq 'second: list<u32>,' "$wit"
grep -Fq 'ticket: own<ticket>,' "$wit"
grep -Fq 'make-ticket: func(seed: u32) -> own<ticket>;' "$wit"
grep -Fq 'consume-via-stream: async func(' "$wit"
grep -Fq 'data: stream<two-list-entry>' "$wit"
grep -Fq 'world owned-record-two-list-producer' "$wit"
grep -Fq 'export produce: async func(mode: u32) -> result<_, error-code>;' "$wit"
if grep -Eq 'do:g6-2-owned-record-(list|pair|triple|nested)-producer|stream<list<|stream<variant' "$wit"; then
  printf 'two-list owned-record producer emitted an out-of-scope neighboring shape\n' >&2
  exit 1
fi

for marker in \
  '[producer-record-byte-size] 20' \
  '[producer-record-alignment] 4' \
  '[producer-first-pointer-offset] 0' \
  '[producer-first-length-offset] 4' \
  '[producer-second-pointer-offset] 8' \
  '[producer-second-length-offset] 12' \
  '[producer-ticket-offset] 16' \
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
  printf 'two-list owned-record producer emitted an ARC symbol\n' >&2
  exit 1
fi
if grep -Eq '\(ref (null|extern|func|eq|struct|array)' "$wat"; then
  printf 'two-list owned-record producer crossed a Wasm GC reference boundary\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-two-list-producer \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

printf 'G6.2 two-list owned-record producer Do Component gate passed record-size=20 list-capacity=3 list-releases=2 drops=1\n'
