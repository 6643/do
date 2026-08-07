#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/g6-2-c-min-dynamic-list-resource-producer.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-g6-2-c-min-dynamic-producer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/dynamic-producer.wat"
wit="$tmp_dir/dynamic-producer.wit"
test -x "$do_bin"
test -f "$source"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

test -s "$core_wat"
test -s "$wit"
grep -Fq '[producer-list-pointer]' "$core_wat"
grep -Fq '[producer-list-length]' "$core_wat"
grep -Fq '[producer-list-element-stride]' "$core_wat"
grep -Fq '[producer-list-ticket-offset]' "$core_wat"
grep -Fq '[producer-stream-capacity]' "$core_wat"
grep -Fq '[producer-list-transfer]' "$core_wat"
grep -Fq '[producer-child-before-parent-cleanup]' "$core_wat"
grep -Fq 'i32.const 3' "$core_wat"
grep -Fq 'export produce: async func(count: u32)' "$wit"
grep -Fq 'world dynamic-list-producer' "$wit"

core_wasm="$tmp_dir/dynamic-producer.core.wasm"
embedded="$tmp_dir/dynamic-producer.embedded.wasm"
component="$tmp_dir/dynamic-producer.component.wasm"
wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world dynamic-list-producer \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded"
wasm-tools component new --skip-validation "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"
printf 'G6.2 bounded dynamic list producer compiler gate passed\n'
