#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$repo_root/src/build/test/compile_ok/540_wasi_filesystem_open_at_component.do"
output=$(mktemp /tmp/do-d2-open-at-compiler.XXXXXX.wat)
stderr=$(mktemp /tmp/do-d2-open-at-compiler.XXXXXX.stderr)

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-output "$output.wit" -o "$output" \
  >"$output.stdout" 2>"$stderr"

for marker in \
  'wasi:filesystem/types@0.3.0-rc-2025-09-16' \
  '[async-lower][method]descriptor.open-at' \
  '[resource-drop]descriptor' \
  '[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run' \
  '[open-at-call]' \
  '[open-at-result-area]' \
  '[open-at-path-copy]' \
  '[open-at-ready]' \
  '[open-at-error]' \
  '[open-at-pending]'; do
  grep -Fq "$marker" "$output" || {
    printf 'missing compiler marker: %s\n' "$marker" >&2
    exit 1
  }
done

printf 'D2 filesystem descriptor.open-at compiler gate passed\n'
