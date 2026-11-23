#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-tuple-list-lift.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

"$zig_bin" run "$repo_root/src/gc_marshal_tuple_probe_main.zig" -- \
  "$repo_root/examples/gc-p3-runtime/marshal-tuple-list-lift-assembly.wit" \
  "$tmp_dir/core.wat" "$repo_root"
"$toolchain_bin" parse-core "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"
rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$tmp_dir/core.wat"
rg -q '\(import "demo:marshal-tuple-list-lift/api@1.0.0" "receive"' "$tmp_dir/core.wat"
rg -q 'struct.new \$do_tuple' "$tmp_dir/core.wat"
rg -q 'array.set \$do_u8' "$tmp_dir/core.wat"
test "$(rg -c 'call \$cabi_realloc' "$tmp_dir/core.wat")" -eq 1
call_line=$(rg -n 'call \$canonical_call' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
free_line=$(rg -n 'call \$cabi_realloc' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
if [ -z "$call_line" ] || [ -z "$free_line" ] || [ "$call_line" -ge "$free_line" ]; then
  printf 'Tuple byte-list lift call/free order is invalid\n' >&2
  exit 1
fi

"$toolchain_bin" embed-component "$repo_root/examples/gc-p3-runtime/marshal-tuple-list-lift-assembly.wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none

output=$( \
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-tuple-list-lift-host-runner -- "$tmp_dir/component.wasm"
)
rg -Fq 'GC Tuple byte-list lift host execution passed result=770 receive-calls=1' <<<"$output"
printf '%s\n' "$output"
