#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
wasm_tools_bin=${WASM_TOOLS:-wasm-tools}
source="$repo_root/examples/p3-runtime/g6-2-scalar-list-producer.do"
probe_wit="$repo_root/examples/p3-runtime/wit/g6-2-scalar-list-producer.wit"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-scalar-list-producer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/scalar-list-producer.wat"
wit="$tmp_dir/scalar-list-producer.wit"
core_wasm="$tmp_dir/scalar-list-producer.core.wasm"
embedded="$tmp_dir/scalar-list-producer.embedded.wasm"
component="$tmp_dir/scalar-list-producer.component.wasm"

test -x "$do_bin"
test -f "$source"
test -f "$probe_wit"
command -v "$wasm_tools_bin" >/dev/null 2>&1

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"

grep -Fq 'package do:g6-2-scalar-list-producer@0.1.0;' "$wit"
grep -Fq 'consume-via-stream: async func(data: stream<list<u32>>) -> result<_, error-code>;' "$wit"
grep -Fq 'world scalar-list-producer' "$wit"
grep -Fq 'export produce: async func(count: u32) -> result<_, error-code>;' "$wit"
if grep -Eq 'do:g6-2-(c-min|batched|dynamic)-|own<|borrow<|ref<|resource|pointer|reference' "$wit"; then
  printf 'scalar-list producer emitted an out-of-scope package or ownership marker\n' >&2
  exit 1
fi

for marker in \
  '[producer-list-pointer]' \
  '[producer-list-length]' \
  '[producer-list-element-stride]' \
  '[producer-list-capacity]' \
  '[producer-stream-item-slot]' \
  '[producer-list-transfer]' \
  '[producer-list-release-exactly-once]' \
  '[producer-cancel-before-transfer]'; do
  grep -Fq "$marker" "$core_wat"
done

marker_value() {
  local marker="$1"
  awk -v marker="$marker" '
    $0 ~ "^[[:space:]]*;; \\[" marker "\\]$" { want = 1; next }
    want && $1 == "i32.const" { print $2; exit }
    want { exit 1 }
  ' "$core_wat"
}

test "$(marker_value 'producer-list-pointer')" = 64
test "$(marker_value 'producer-list-length')" = 68
test "$(marker_value 'producer-list-element-stride')" = 4
test "$(marker_value 'producer-list-capacity')" = 3
test "$(marker_value 'producer-stream-item-slot')" = 0

if grep -Fq '[resource-drop]' "$core_wat"; then
  printf 'scalar-list producer unexpectedly imports resource-drop\n' >&2
  exit 1
fi

cmp "$wit" "$probe_wit"
"$wasm_tools_bin" parse "$core_wat" -o "$core_wasm"
"$wasm_tools_bin" component embed "$wit" "$core_wasm" \
  --world scalar-list-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
"$wasm_tools_bin" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools_bin" validate --features cm-async,cm-more-async-builtins "$component"

printf 'G6.2 scalar list producer Do Component gate passed\n'
