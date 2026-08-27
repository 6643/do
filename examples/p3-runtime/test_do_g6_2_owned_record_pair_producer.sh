#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
wasm_tools_bin=${WASM_TOOLS:-wasm-tools}
source="$repo_root/examples/p3-runtime/g6-2-owned-record-pair-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-pair-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-owned-record-pair-producer.XXXXXX")
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

core_wat="$tmp_dir/owned-record-pair-producer.wat"
wit="$tmp_dir/owned-record-pair-producer.wit"
core_wasm="$tmp_dir/owned-record-pair-producer.core.wasm"
embedded="$tmp_dir/owned-record-pair-producer.embedded.wasm"
component="$tmp_dir/owned-record-pair-producer.component.wasm"

test -x "$do_bin"
test -f "$source"
test -f "$probe_wit"
command -v "$wasm_tools_bin" >/dev/null 2>&1

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"
cmp "$wit" "$probe_wit"
test "$(sha256sum "$wit" | awk '{print $1}')" = \
  89345a5213936735d7f065cd54ed42b83d159b80305a1a900ae00df2e811704d

grep -Fq 'package do:g6-2-owned-record-pair-producer@0.1.0;' "$wit"
grep -Fq 'record resource-pair {' "$wit"
grep -Fq 'left: own<ticket>,' "$wit"
grep -Fq 'right: own<ticket>,' "$wit"
grep -Fq 'data: stream<resource-pair>' "$wit"
grep -Fq 'world owned-record-pair-producer' "$wit"
grep -Fq 'export produce: async func(mode: u32) -> result<_, error-code>;' "$wit"
if grep -Eq 'do:g6-2-(c-min|batched|dynamic|scalar-list|owned-record)-producer|stream<list<|stream<variant' "$wit"; then
  printf 'owned-record pair producer emitted an out-of-scope neighboring shape\n' >&2
  exit 1
fi

for marker in \
  '[producer-record-byte-size] 8' \
  '[producer-record-left-offset] 0' \
  '[producer-record-right-offset] 4' \
  '[producer-stream-capacity] 1' \
  '[producer-left-ticket-seed] 111' \
  '[producer-right-ticket-seed] 222' \
  '[producer-record-transfer]' \
  '[producer-resource-drop-exactly-once]' \
  '[producer-child-before-parent-cleanup]'; do
  grep -Fq ";; $marker" "$core_wat"
done
grep -Fq '[async-lift]produce' "$core_wat"
if grep -Fq '__arc_' "$core_wat"; then
  printf 'owned-record pair producer emitted an ARC symbol\n' >&2
  exit 1
fi

"$wasm_tools_bin" parse "$core_wat" -o "$core_wasm"
"$wasm_tools_bin" component embed "$wit" "$core_wasm" \
  --world owned-record-pair-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
"$wasm_tools_bin" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools_bin" validate --features cm-async,cm-more-async-builtins "$component"

printf 'G6.2 owned-record pair producer Do Component gate passed\n'
