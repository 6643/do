#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

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
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-record-mixed-text-two-u32-lists-lift-call.do
descriptor=demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift
wit=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-text-two-u32-lists-lift-assembly.wit
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-mixed-text-two-u32-lists-lift-host.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$toolchain_bin" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing do-toolchain or Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$input_do" \
  --gc-wit-marshal "$descriptor" -o "$tmp_dir/core.wat"
"$toolchain_bin" parse-core "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"
rg -q '^  \(type \$canonical_lift \(func \(param i32\)\)\)' "$tmp_dir/core.wat"
rg -q '\(import "demo:marshal-record-mixed-text-two-u32-lists-lift/api@1.0.0" "read"' "$tmp_dir/core.wat"
rg -q '\(global \$__marshal_heap \(mut i32\) \(i32.const 28\)\)' "$tmp_dir/core.wat"
if rg -q '__arc_' "$tmp_dir/core.wat"; then
  printf 'explicit mixed text/two-u32-lists record lift route still contains ARC symbols\n' >&2
  exit 1
fi
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/core.wat"; then
  printf 'GC reference crossed canonical mixed text/two-u32-lists record lift import\n' >&2
  exit 1
fi
rg -q 'array.new_default \$do_bytes' "$tmp_dir/core.wat"
test "$(rg -c 'array.new_default \$do_u32' "$tmp_dir/core.wat")" -eq 2
test "$(rg -c 'call \$cabi_realloc' "$tmp_dir/core.wat")" -eq 3
rg -q 'struct.new \$do_record' "$tmp_dir/core.wat"

"$toolchain_bin" embed-component "$wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-mixed-text-two-u32-lists-lift-host-runner -- \
    "$tmp_dir/component.wasm"
)
grep -Fq 'GC mixed text/two-u32-lists record lift host adapter passed code=7 label=hello first=[10, 20, 5] second=[3, 4] result=54 stats=51 read-calls=1 allocations=3 frees=3' <<<"$output"
printf '%s\n' "$output"
printf 'manifest-backed mixed text/two-u32-lists record lift Component host execution passed\n'
