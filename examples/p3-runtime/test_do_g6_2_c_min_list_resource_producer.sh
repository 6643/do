#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source="$repo_root/examples/p3-runtime/g6-2-c-min-list-resource-producer.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-g6-2-c-min-producer.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/c-min-producer.wat"
test -x "$do_bin"
test -f "$source"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component -o "$core_wat"

test -s "$core_wat"
grep -Fq '[producer-list-pointer]' "$core_wat"
grep -Fq '[producer-list-length]' "$core_wat"
grep -Fq '[producer-list-element-stride]' "$core_wat"
grep -Fq '[producer-list-ticket-offset]' "$core_wat"
grep -Fq '[producer-stream-capacity]' "$core_wat"
grep -Fq '[producer-list-transfer]' "$core_wat"
grep -Fq '[producer-child-before-parent-cleanup]' "$core_wat"

wasm-tools parse "$core_wat" -o "$tmp_dir/c-min-producer.core.wasm"
printf 'G6.2 C-min producer compiler gate passed\n'
