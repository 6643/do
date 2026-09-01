#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
fixture="$repo_root/examples/p3-runtime/two-await-component.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-async-frame-component.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler: %s\n' "$do_bin" >&2
  exit 1
fi
if [ ! -x "$wasmtime_bin" ]; then
  printf 'missing Wasmtime executable: %s\n' "$wasmtime_bin" >&2
  exit 1
fi

wat_path="$tmp_dir/two-await.wat"
wit_path="$tmp_dir/two-await.wit"
core_path="$tmp_dir/two-await.core.wasm"
embedded_path="$tmp_dir/two-await.embedded.wasm"
component_path="$tmp_dir/two-await.component.wasm"

(cd "$repo_root" && DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-wait-for-component --p3-wit-output "$wit_path" -o "$wat_path"
)

if grep -Fq '__arc_' "$wat_path"; then
  printf 'bounded async GC frame output contains ARC markers\n' >&2
  exit 1
fi
for marker in \
  '(type $async-frame (struct' \
  '(table $async-frames 0 (ref null $async-frame))' \
  'table.get $async-frames' \
  'struct.get $async-frame $waitable-set'; do
  if ! grep -Fq "$marker" "$wat_path"; then
    printf 'bounded async GC frame output is missing marker: %s\n' "$marker" >&2
    exit 1
  fi
done
if grep -Fq 'global $frame-next' "$wat_path"; then
  printf 'bounded async GC frame output still uses linear-memory frame allocation\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$wat_path" -o "$core_path"
"$wasmtime_bin" compile -W gc=y -o "$tmp_dir/two-await.compiled" "$wat_path"
"$toolchain_bin" embed-component "$wit_path" "$core_path" probe --features component-async -o "$embedded_path"
"$toolchain_bin" new-component "$embedded_path" -o "$component_path"
"$toolchain_bin" validate-component "$component_path" --features component-async

printf 'Do bounded async GC frame/table component passed: fixture=%s\n' \
  "$(basename "$fixture")"
