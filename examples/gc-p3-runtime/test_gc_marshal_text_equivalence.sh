#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
wit="$repo_root/examples/gc-p3-runtime/marshal-text-equivalence.wit"
gc_core_wat="$repo_root/examples/gc-p3-runtime/marshal-text-equivalence-gc.core.wat"
arc_core_wat="$repo_root/examples/gc-p3-runtime/marshal-text-equivalence-arc.core.wat"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

tool_version=$("$wasm_tools_bin" --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac

if [ ! -f "$wit" ] || [ ! -f "$gc_core_wat" ] || [ ! -f "$arc_core_wat" ]; then
  printf 'missing text marshal equivalence fixture\n' >&2
  exit 1
fi
if [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Rust runner linker: CC=%s CXX=%s LINKER=%s\n' "$cc_bin" "$cxx_bin" "$linker_bin" >&2
  exit 1
fi

"$wasm_tools_bin" parse "$gc_core_wat" -o "$tmp_dir/gc-core.wasm"
"$wasm_tools_bin" parse "$arc_core_wat" -o "$tmp_dir/arc-core.wasm"
"$wasm_tools_bin" component embed "$wit" "$tmp_dir/gc-core.wasm" --world probe -o "$tmp_dir/gc-embedded.wasm"
"$wasm_tools_bin" component embed "$wit" "$tmp_dir/arc-core.wasm" --world probe -o "$tmp_dir/arc-embedded.wasm"
"$wasm_tools_bin" component new "$tmp_dir/gc-embedded.wasm" -o "$tmp_dir/gc.component.wasm"
"$wasm_tools_bin" component new "$tmp_dir/arc-embedded.wasm" -o "$tmp_dir/arc.component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/gc.component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/arc.component.wasm"

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-text-host-runner -- \
    "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/ARC text marshal equivalence passed values=hello allocations=1/1 frees=1/1' <<<"$output"
printf '%s\n' "$output"
