#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/generic-abi-v2-promotion.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

DO_P3_ASYNC_COMPONENT_TARGET=--p3-async-component-v2 \
  bash "$repo_root/examples/p3-runtime/test_do_variant_resource_stream_lowering.sh"
DO_GENERIC_ABI_V2_SCALAR_TARGET=--p3-async-component-v2 \
  bash "$repo_root/examples/wit-bindgen-do/test_generic_abi_v2_scalar_i64.sh"

mkdir -p "$tmp_dir/wit"
cp "$repo_root/examples/wit-bindgen-do/project/scalar_async_main.do" "$tmp_dir/scalar_async_main.do"
"$do_bin" wit bind "$repo_root/examples/p3-runtime/wit/generic-async-scalar-probe.wit" \
  --world probe --out "$tmp_dir/wit"

rejected_wat="$tmp_dir/scalar-u32.wat"
if "$do_bin" build "$tmp_dir/scalar_async_main.do" \
    --p3-async-component-v2 -o "$rejected_wat" \
    >"$tmp_dir/scalar-u32.stdout" 2>"$tmp_dir/scalar-u32.stderr"; then
  printf 'expected Generic ABI v2 profile to reject generated Future<u32>\n' >&2
  exit 1
fi
test ! -e "$rejected_wat"
grep -Fq 'UnsupportedGenericAbiV2Promotion' "$tmp_dir/scalar-u32.stderr"

printf 'generic ABI v2 promotion Component/Rust/Wasmtime gates passed\n'
