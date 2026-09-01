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
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-u32-list-lower-host.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

(cd "$repo_root" && "$do_bin" build "$input_do" --gc-wit-marshal "$descriptor" -o "$tmp_dir/core.wat")
"$toolchain_bin" parse-core "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"
rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32\)\)\)' "$tmp_dir/core.wat"
rg -q '\(import "demo:marshal-record-u32-list-lower/api@1.0.0" "write"' "$tmp_dir/core.wat"
if rg -q '__arc_' "$tmp_dir/core.wat"; then
  printf 'explicit u32-list record lower route still contains ARC symbols\n' >&2
  exit 1
fi
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/core.wat"; then
  printf 'GC reference crossed canonical u32-list record lower import\n' >&2
  exit 1
fi
rg -q 'array.get \$do_u32' "$tmp_dir/core.wat"
rg -q 'i32.store' "$tmp_dir/core.wat"
test "$(rg -c 'call \$cabi_realloc' "$tmp_dir/core.wat")" -eq 2
call_line=$(rg -n 'call \$canonical_call' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
free_line=$(rg -n 'call \$cabi_realloc' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
if [ -z "$call_line" ] || [ -z "$free_line" ] || [ "$call_line" -ge "$free_line" ]; then
  printf 'u32-list record lower call/free order is invalid\n' >&2
  exit 1
fi

"$toolchain_bin" embed-component "$wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-u32-list-lower-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC u32-list record lower host adapter passed code=7 payload=[10, 20, 30] result=42 write-calls=1 allocations=1 frees=1' <<<"$output"
printf '%s\n' "$output"
printf 'manifest-backed u32-list record lower Component host execution passed\n'
