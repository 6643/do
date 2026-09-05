#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
do_bin="${DO_BIN:-$repo_root/bin/do}"
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-component-boundary.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

test -x "$do_bin"
test -x "$toolchain_bin"

core_wat="$tmp_dir/map-lower.core.wat"
lift_wat="$tmp_dir/map-lift.core.wat"
injected_wat="$tmp_dir/map-lower.injected.wat"
injected_wasm="$tmp_dir/map-lower.injected.wasm"
injected_embedded="$tmp_dir/map-lower.injected.embedded.wasm"

"$do_bin" build "$repo_root/examples/gc-p3-runtime/map-u32-u32-lower.do" \
  --gc-wit-marshal demo:marshal-map-u32-u32/api.write@1.0.0/lower \
  -o "$core_wat"

if rg -q '\(import .*(\(param|\(result).*\(ref' "$core_wat"; then
  printf 'GC reference crossed the canonical Component import boundary\n' >&2
  exit 1
fi
if rg -q '__arc_' "$core_wat"; then
  printf 'GC Component marshal route contains an ARC marker\n' >&2
  exit 1
fi
rg -q '\[linear-temp-free\].*count=1' "$core_wat"

"$do_bin" build "$repo_root/examples/gc-p3-runtime/map-u32-u32-lift.do" \
  --gc-wit-marshal demo:marshal-map-u32-u32/api.read@1.0.0/lift \
  -o "$lift_wat"
if rg -q '\(import .*(\(param|\(result).*\(ref' "$lift_wat"; then
  printf 'GC reference crossed the canonical Component result boundary\n' >&2
  exit 1
fi
if rg -q '__arc_' "$lift_wat"; then
  printf 'GC Component lift route contains an ARC marker\n' >&2
  exit 1
fi
rg -q '\[linear-temp-free\].*count=1' "$lift_wat"

# Core validation accepts GC reference imports. Component construction must
# reject the same shape when the WIT signature requires canonical i32 words.
sed 's/(type \$canonical_lower (func (param i32 i32)))/(type $canonical_lower (func (param (ref null $do_map) i32)))/' \
  "$core_wat" >"$injected_wat"
"$toolchain_bin" parse-core "$injected_wat" -o "$injected_wasm"
"$toolchain_bin" embed-component \
  "$repo_root/examples/gc-p3-runtime/marshal-map-u32-u32-lower-assembly.wit" \
  "$injected_wasm" probe --features component-map -o "$injected_embedded"
if "$toolchain_bin" new-component "$injected_embedded" -o "$tmp_dir/injected.component.wasm" >"$tmp_dir/injected.stdout" 2>"$tmp_dir/injected.stderr"; then
  printf 'Component construction unexpectedly accepted a GC reference import\n' >&2
  exit 1
fi
rg -q 'type mismatch|Ref\(' "$tmp_dir/injected.stderr"

bash "$repo_root/examples/p3-runtime/test_rust_wasi_filesystem_sync.sh" >"$tmp_dir/filesystem.stdout"
rg -q 'D2 filesystem descriptor\.sync Rust/Wasmtime runtime passed' "$tmp_dir/filesystem.stdout"

printf 'GC Component boundary and resource cleanup gate passed\n'
