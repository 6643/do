#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
wit="$repo_root/examples/gc-p3-runtime/marshal-u32-host.wit"
core_wat="$repo_root/examples/gc-p3-runtime/marshal-u32-host.core.wat"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-u32.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$toolchain_bin" ]; then
  printf 'missing do-toolchain executable: %s\n' "$toolchain_bin" >&2
  exit 1
fi
if [ ! -x "$wasmtime_bin" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Wasmtime or Rust runner linker\n' >&2
  exit 1
fi

"$toolchain_bin" parse-core "$core_wat" -o "$tmp_dir/core.wasm"
if grep -E '^[[:space:]]*\(import .*\(ref' "$core_wat" >"$tmp_dir/gc-import.stderr"; then
  cat "$tmp_dir/gc-import.stderr" >&2
  exit 1
fi
"$toolchain_bin" embed-component "$wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none
"$toolchain_bin" component-wit "$tmp_dir/component.wasm" >"$tmp_dir/component.wit"
grep -Fq 'send: func(value: list<u32>)' "$tmp_dir/component.wit"

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-u32-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC list<u32> host adapter passed values=[10, 20, 30]' <<<"$output"
printf '%s\n' "$output"

printf 'bounded GC list<u32> host Component assembly passed\n'
