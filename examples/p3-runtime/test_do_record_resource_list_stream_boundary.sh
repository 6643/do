#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/record-resource-list-stream-boundary.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit="$repo_root/examples/p3-runtime/wit/record-resource-list-stream-probe.wit"
core_wat="$tmp_dir/record-resource-stream.wat"
core_wasm="$tmp_dir/record-resource-stream.wasm"
embedded="$tmp_dir/record-resource-list-stream.embedded.wasm"
stderr_file="$tmp_dir/list-stream.stderr"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  --p3-async-component \
  "$repo_root/examples/p3-runtime/record-resource-stream-probe-component.do" \
  -o "$core_wat" >/dev/null
"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" \
  record-resource-list-stream-probe -o "$embedded"

if DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  --p3-async-component \
  "$repo_root/examples/p3-runtime/record-resource-list-stream-unregistered-component.do" \
  -o "$tmp_dir/list-stream.wat" >"$tmp_dir/list-stream.stdout" 2>"$stderr_file"; then
  echo "record-resource list stream unexpectedly lowered" >&2
  exit 1
fi

grep -Fq 'UnsupportedP3AsyncComponent' "$stderr_file"
printf 'record-resource list stream WIT acceptance and Do rejection passed\n'
