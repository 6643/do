#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-triple-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-triple-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-triple-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

core_wat="$tmp_dir/owned-record-triple-producer.wat"
wit="$tmp_dir/owned-record-triple-producer.wit"
core_wasm="$tmp_dir/owned-record-triple-producer.core.wasm"
embedded="$tmp_dir/owned-record-triple-producer.embedded.wasm"
component="$tmp_dir/owned-record-triple-producer.component.wasm"

test -x "$do_bin"
test -f "$source"
test -f "$probe_wit"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1

grep -Fq 'package do:g6-2-owned-record-triple-producer@0.1.0;' "$wit"
grep -Fq 'record resource-triple {' "$wit"
grep -Fq 'left: own<ticket>,' "$wit"
grep -Fq 'middle: own<ticket>,' "$wit"
grep -Fq 'right: own<ticket>,' "$wit"
grep -Fq 'make-ticket: func(seed: u32) -> own<ticket>;' "$wit"
grep -Fq 'data: stream<resource-triple>' "$wit"
grep -Fq 'world owned-record-triple-producer' "$wit"
grep -Fq 'export produce: async func(' "$wit"
grep -Fq 'middle-seed: u32' "$wit"
grep -Fq 'right-seed: u32' "$wit"
if grep -Eq 'do:g6-2-(c-min|batched|dynamic|scalar-list)-|do:g6-2-owned-record-(producer|pair|pair-parameterized)-|stream<list<|stream<variant' "$wit"; then
  printf 'owned-record triple producer emitted an out-of-scope neighboring shape\n' >&2
  exit 1
fi

for marker in \
  '[producer-record-byte-size] 12' \
  '[producer-record-middle-offset] 4' \
  '[producer-record-right-offset] 8' \
  '[producer-input-word-count] 4' \
  '[producer-record-transfer]' \
  '[producer-resource-drop-exactly-once]'; do
  grep -Fq ";; $marker" "$core_wat"
done
grep -Fq 'do:g6-2-owned-record-triple-producer/sink@0.1.0' "$core_wat"
grep -Fq '(func (export "[async-lift]produce")' "$core_wat"
if grep -Fq '__arc_' "$core_wat"; then
  printf 'owned-record triple producer emitted an ARC symbol\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" owned-record-triple-producer \
  -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"

printf 'G6.2 owned-record triple producer Do Component gate passed\n'
