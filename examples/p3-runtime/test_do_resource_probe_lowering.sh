#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
source_file="$repo_root/examples/p3-runtime/resource-probe.do"
expected_wit="$repo_root/examples/p3-runtime/wit/resource-probe.wit"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

"$do_bin" build "$source_file" \
  --p3-resource-probe-component \
  --p3-wit-output "$tmp_dir/probe.wit" \
  -o "$tmp_dir/probe.wat" >/dev/null

cmp "$expected_wit" "$tmp_dir/probe.wit"
wasm-tools parse "$tmp_dir/probe.wat" -o "$tmp_dir/probe.wasm"
wasm-tools component embed "$tmp_dir/probe.wit" --world probe -o "$tmp_dir/probe.embedded.wasm" "$tmp_dir/probe.wasm"
wasm-tools component new -o "$tmp_dir/probe.component.wasm" "$tmp_dir/probe.embedded.wasm"
wasm-tools component wit "$tmp_dir/probe.component.wasm" | grep -Fq 'borrow-value: func(ticket: borrow<ticket>) -> u32'

sed 's/return value/return seed/' "$source_file" >"$tmp_dir/changed.do"
if "$do_bin" build "$tmp_dir/changed.do" --p3-resource-probe-component -o "$tmp_dir/changed.wat" >"$tmp_dir/changed.stdout" 2>"$tmp_dir/changed.stderr"; then
  printf 'changed resource probe source unexpectedly lowered\n' >&2
  exit 1
fi
grep -Fq 'UnsupportedResourceProbeComponent' "$tmp_dir/changed.stderr"

printf 'resource probe lowering verified\n'
