#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
wasm_tools_bin=${WASM_TOOLS:-wasm-tools}
source="$repo_root/examples/p3-runtime/g6-2-batched-list-resource-producer.do"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/do-g6-2-batched-list-resource-producer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/batched-producer.wat"
wit="$tmp_dir/batched-producer.wit"
core_wasm="$tmp_dir/batched-producer.core.wasm"
embedded="$tmp_dir/batched-producer.embedded.wasm"
component="$tmp_dir/batched-producer.component.wasm"

test -x "$do_bin"
test -f "$source"
command -v "$wasm_tools_bin" >/dev/null 2>&1

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"

grep -Fq 'package do:g6-2-batched-list-producer@0.1.0;' "$wit"
grep -Fq 'data: stream<list<resource-entry>>' "$wit"
grep -Fq 'world batched-list-producer' "$wit"
grep -Fq 'export produce: async func(mode: u32)' "$wit"

if grep -Eq 'do:g6-2-c-min|dynamic-list-producer|c-min-producer' "$wit" "$core_wat"; then
  printf 'batched producer emitted a neighboring producer package marker\n' >&2
  exit 1
fi

for marker in \
  'producer-list-pointer' \
  'producer-list-length' \
  'producer-list-pointer-batch-1' \
  'producer-list-length-batch-1' \
  'producer-list-element-stride' \
  'producer-list-ticket-offset' \
  'producer-stream-capacity' \
  'producer-batch-0' \
  'producer-batch-1' \
  'producer-batch-transfer-0' \
  'producer-batch-transfer-1' \
  'producer-batch-child-before-parent-cleanup' \
  'producer-batch-list-release'; do
  grep -Eq "^[[:space:]]*;; \\[$marker\\]$" "$core_wat"
done

grep -Fq 'i32.const 111' "$core_wat"
grep -Fq 'i32.const 222' "$core_wat"
grep -Fq 'i32.const 333' "$core_wat"
grep -Fq '[producer-batched-list-transfer]' "$core_wat"
grep -Fq '[producer-batched-child-before-parent-cleanup]' "$core_wat"
grep -Fq '[producer-batched-plan-layout] pointer=64 length=68 stride=4 ticket-offset=0 capacity=1 batches=2 lengths=2,1' "$core_wat"

if grep -Eq '\(func \(export "[^" ]*(helper|batch|stream)[^" ]*"' "$core_wat"; then
  printf 'batched producer exported a private helper\n' >&2
  exit 1
fi

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
test "$(marker_value 'producer-list-ticket-offset')" = 0
test "$(marker_value 'producer-stream-capacity')" = 1

"$wasm_tools_bin" parse "$core_wat" -o "$core_wasm"
"$wasm_tools_bin" component embed "$wit" "$core_wasm" \
  --world batched-list-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
"$wasm_tools_bin" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools_bin" validate --features cm-async,cm-more-async-builtins "$component"

printf 'G6.2 batched list producer Do compiler Component gate passed\n'
