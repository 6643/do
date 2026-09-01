#!/usr/bin/env bash
# Verification Status: complete
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
wit_dir="$repo_root/examples/gc-p3-runtime/wasi-random-gc-lift-package"
probe="$repo_root/src/gc_wasi_random_probe_main.zig"
arc_core="$repo_root/examples/gc-p3-runtime/wasi-random-list-lift-arc.core.wat"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-wasi-random-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [[ ! -x "$runner_cc" ]]; then
  printf 'missing Rust runner linker: %s\n' "$runner_cc" >&2
  exit 1
fi

"$zig_bin" run "$probe" -- "$tmp_dir/gc.core.wat" "$repo_root"
cp "$arc_core" "$tmp_dir/arc.core.wat"

for name in gc arc; do
  "$toolchain_bin" parse-core "$tmp_dir/$name.core.wat" -o "$tmp_dir/$name.core.wasm"
  "$toolchain_bin" embed-component "$wit_dir" "$tmp_dir/$name.core.wasm" probe --features none -o "$tmp_dir/$name.embedded.wasm"
  "$toolchain_bin" new-component "$tmp_dir/$name.embedded.wasm" -o "$tmp_dir/$name.component.wasm"
  "$toolchain_bin" validate-component "$tmp_dir/$name.component.wasm" --features none
done

output=$(
  CC="$runner_cc" CXX="$runner_cc" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_cc" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-wasi-random-equivalence-runner -- \
    "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/ARC WASI random list<u8> equivalence passed lengths=16/16 bytes=16/16 calls=1/1' <<<"$output"
printf '%s\n' "$output"
