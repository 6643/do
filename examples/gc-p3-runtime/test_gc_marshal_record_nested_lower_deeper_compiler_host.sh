#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
do_bin=$repo_root/bin/do
input_do=$repo_root/src/build/test/compile_ok/587_gc_wit_nested_record_deeper_lower_host_boundary.do
descriptor=demo:marshal-record-nested-lower-deeper/api.write@1.0.0/lower
wit=$repo_root/examples/gc-p3-runtime/marshal-record-nested-lower-deeper-assembly.wit
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-nested-lower-deeper-compiler-host.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$toolchain_bin" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing do-toolchain or Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

"$do_bin" build "$input_do" --gc-wit-marshal "$descriptor" -o "$tmp_dir/core.wat"
"$toolchain_bin" parse-core "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"
rg -q '\(type \$canonical_lower \(func \(param i32 i64 i64 i64 i64\)\)\)' "$tmp_dir/core.wat"
rg -q '\(import "demo:marshal-record-nested-lower-deeper/api@1.0.0" "write"' "$tmp_dir/core.wat"
rg -q 'struct.get \$do_leaf \$field1' "$tmp_dir/core.wat"
rg -q 'struct.get \$do_header \$field1' "$tmp_dir/core.wat"
rg -q 'struct.get \$do_detail \$field1' "$tmp_dir/core.wat"
rg -q 'struct.get \$do_record \$field1' "$tmp_dir/core.wat"
rg -q '\(export "run" \(func \$run\)\)' "$tmp_dir/core.wat"
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/core.wat"; then
  printf 'GC reference crossed canonical four-level nested lower import\n' >&2
  exit 1
fi

"$toolchain_bin" embed-component "$wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-nested-lower-deeper-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC four-level nested scalar record lower host adapter passed result=42 write-calls=1' <<<"$output"
printf '%s\n' "$output"
printf 'compiler-wired four-level nested scalar record lower Component host execution passed\n'
