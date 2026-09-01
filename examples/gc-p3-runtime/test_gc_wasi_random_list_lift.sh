#!/usr/bin/env bash
# Verification Status: verified
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
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-wasi-random.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

"$zig_bin" run "$probe" -- "$tmp_dir/core.wat" "$repo_root"
"$toolchain_bin" parse-core "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"
if grep -E '^[[:space:]]*\(import .*(\(param|\(result).*\(ref' "$tmp_dir/core.wat" >"$tmp_dir/gc-import.stderr"; then
  cat "$tmp_dir/gc-import.stderr" >&2
  exit 1
fi
grep -Fq '(type $canonical_lift (func (param i64 i32)))' "$tmp_dir/core.wat"
grep -Fq 'i64.const 16' "$tmp_dir/core.wat"

"$toolchain_bin" embed-component "$wit_dir" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none
"$toolchain_bin" component-wit "$tmp_dir/component.wasm" >"$tmp_dir/component.wit"
grep -Fq 'get-random-bytes: func(len: u64) -> list<u8>' "$tmp_dir/component.wit"
grep -Fq 'export run: func() -> u32' "$tmp_dir/component.wit"

mutated_root="$tmp_dir/mutated-repository"
random_relative='src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/random/random.wit'
mkdir -p "$mutated_root/$(dirname "$random_relative")" "$mutated_root/doc/wit"
cp "$repo_root/$random_relative" "$mutated_root/$random_relative"
cp "$repo_root/doc/wit/gc_random_imports.wit" "$mutated_root/doc/wit/gc_random_imports.wit"
cp "$repo_root/doc/wit/gc_descriptor_manifest.json" "$mutated_root/doc/wit/gc_descriptor_manifest.json"
printf '\n' >> "$mutated_root/$random_relative"
if mutated_output=$("$zig_bin" run "$probe" -- "$tmp_dir/mutated.wat" "$mutated_root" 2>&1); then
  printf 'mutated descriptor source unexpectedly passed the manifest hash gate\n' >&2
  exit 1
fi
grep -Fq 'SourceHashMismatch' <<<"$mutated_output"

output=$(
  CC="$runner_cc" CXX="$runner_cc" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_cc" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-wasi-random-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC WASI random list<u8> host lift passed length=16 bytes=16' <<<"$output"
printf '%s\n' "$output"
printf 'bounded WASI random list<u8> GC Component lift passed\n'
