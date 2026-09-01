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
wit="$repo_root/examples/gc-p3-runtime/marshal-text-equivalence.wit"
probe="$repo_root/src/gc_marshal_text_probe_main.zig"
arc_core_wat="$repo_root/examples/gc-p3-runtime/marshal-text-equivalence-arc.core.wat"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
gc_core_wat="$tmp_dir/generated-gc.core.wat"

if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi

if [ ! -f "$wit" ] || [ ! -f "$probe" ] || [ ! -f "$arc_core_wat" ]; then
  printf 'missing text marshal equivalence fixture\n' >&2
  exit 1
fi
if [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Rust runner linker: CC=%s CXX=%s LINKER=%s\n' "$cc_bin" "$cxx_bin" "$linker_bin" >&2
  exit 1
fi

"$zig_bin" run "$probe" -- "$gc_core_wat" "$repo_root"
if grep -E '^[[:space:]]*\(import .*(\(param|\(result).*\(ref' "$gc_core_wat"; then
  printf 'GC reference crossed the Component ABI\n' >&2
  exit 1
fi
"$toolchain_bin" parse-core "$gc_core_wat" -o "$tmp_dir/gc-core.wasm"
"$toolchain_bin" parse-core "$arc_core_wat" -o "$tmp_dir/arc-core.wasm"
"$toolchain_bin" embed-component "$wit" "$tmp_dir/gc-core.wasm" probe --features none -o "$tmp_dir/gc-embedded.wasm"
"$toolchain_bin" embed-component "$wit" "$tmp_dir/arc-core.wasm" probe --features none -o "$tmp_dir/arc-embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/gc-embedded.wasm" -o "$tmp_dir/gc.component.wasm"
"$toolchain_bin" new-component "$tmp_dir/arc-embedded.wasm" -o "$tmp_dir/arc.component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/gc.component.wasm" --features none
"$toolchain_bin" validate-component "$tmp_dir/arc.component.wasm" --features none

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-text-host-runner -- \
    "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/ARC text marshal equivalence passed values=hello allocations=1/1 frees=1/1' <<<"$output"
printf '%s\n' "$output"
