#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
wit="$repo_root/examples/gc-p3-runtime/marshal-u32-lift-host.wit"
core_wat="$repo_root/examples/gc-p3-runtime/marshal-u32-lift-host.core.wat"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-u32-lift.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

tool_version=$("$wasm_tools_bin" --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac
if [ ! -x "$wasmtime_bin" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Wasmtime or Rust runner linker\n' >&2
  exit 1
fi

"$wasm_tools_bin" parse "$core_wat" -o "$tmp_dir/core.wasm"
if grep -E '^[[:space:]]*\(import .*\(ref' "$core_wat" >"$tmp_dir/gc-import.stderr"; then
  cat "$tmp_dir/gc-import.stderr" >&2
  exit 1
fi
"$wasm_tools_bin" component embed "$wit" "$tmp_dir/core.wasm" --world probe -o "$tmp_dir/embedded.wasm"
"$wasm_tools_bin" component new "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/component.wasm"
"$wasm_tools_bin" component wit "$tmp_dir/component.wasm" >"$tmp_dir/component.wit"
grep -Fq 'receive: func() -> list<u32>' "$tmp_dir/component.wit"

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-u32-lift-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC list<u32> lift host adapter passed checksum=60' <<<"$output"
printf '%s\n' "$output"

printf 'bounded GC list<u32> lift host Component assembly passed\n'
