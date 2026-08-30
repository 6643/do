#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
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
"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" dynamic-list-producer \
  -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"
printf 'G6.2 bounded dynamic list producer compiler gate passed\n'
