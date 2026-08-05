#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/borrowed-resource-rejection.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/core.wat"
core_wasm="$tmp_dir/core.wasm"
wit="$repo_root/examples/p3-runtime/wit/record-resource-stream-borrowed-probe.wit"
embedded="$tmp_dir/embedded.wasm"
stderr_file="$tmp_dir/embed.stderr"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  --p3-async-component \
  "$repo_root/examples/p3-runtime/record-resource-stream-nested-probe-component.do" \
  -o "$core_wat" >/dev/null
wasm-tools parse "$core_wat" -o "$core_wasm"

if wasm-tools component embed "$wit" "$core_wasm" \
  --world record-resource-stream-borrowed \
  --features cm-async,cm-more-async-builtins \
  -o "$embedded" >"$tmp_dir/embed.stdout" 2>"$stderr_file"; then
  echo "borrowed resource stream unexpectedly embedded" >&2
  exit 1
fi

grep -Fq 'contains a `borrow<T>` which is not supported' "$stderr_file"
printf 'pinned wasm-tools borrowed resource stream rejection passed\n'
