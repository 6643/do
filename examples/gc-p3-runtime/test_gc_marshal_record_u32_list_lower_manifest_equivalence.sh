#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-record-u32-list-lower-call.do
descriptor=demo:marshal-record-u32-list-lower/api.write@1.0.0/lower
wit=$repo_root/examples/gc-p3-runtime/marshal-record-u32-list-lower-assembly.wit
arc_core_wat=$repo_root/examples/gc-p3-runtime/marshal-record-u32-list-lower-arc.core.wat
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-u32-list-lower-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

(cd "$repo_root" && "$do_bin" build "$input_do" --gc-wit-marshal "$descriptor" -o "$tmp_dir/gc.core.wat")
"$toolchain_bin" parse-core "$tmp_dir/gc.core.wat" -o "$tmp_dir/gc.core.wasm"
"$toolchain_bin" parse-core "$arc_core_wat" -o "$tmp_dir/arc.core.wasm"
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/gc.core.wat" "$arc_core_wat"; then
  printf 'GC reference crossed canonical u32-list record lower import\n' >&2
  exit 1
fi
rg -q 'array.get \$do_u32' "$tmp_dir/gc.core.wat"
rg -q 'i32.store' "$tmp_dir/gc.core.wat"
test "$(rg -c 'call \$cabi_realloc' "$tmp_dir/gc.core.wat")" -eq 2

"$toolchain_bin" embed-component "$wit" "$tmp_dir/gc.core.wasm" probe --features none -o "$tmp_dir/gc.embedded.wasm"
"$toolchain_bin" embed-component "$wit" "$tmp_dir/arc.core.wasm" probe --features none -o "$tmp_dir/arc.embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/gc.embedded.wasm" -o "$tmp_dir/gc.component.wasm"
"$toolchain_bin" new-component "$tmp_dir/arc.embedded.wasm" -o "$tmp_dir/arc.component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/gc.component.wasm" --features none
"$toolchain_bin" validate-component "$tmp_dir/arc.component.wasm" --features none

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-u32-list-lower-equivalence-runner -- \
    "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/ARC u32-list record lower equivalence passed code=7 payload=[10, 20, 30] result=42/17 allocations=1/1 frees=1/1 write-calls=1/1' <<<"$output"
printf '%s\n' "$output"
printf 'manifest-backed u32-list record lower ARC/GC equivalence passed\n'
