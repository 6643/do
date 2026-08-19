#!/usr/bin/env bash
# Verification Status: complete
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
wit_dir="$repo_root/examples/gc-p3-runtime/wasi-random-gc-lift-package"
probe="$repo_root/src/gc_wasi_random_probe_main.zig"
arc_core="$repo_root/examples/gc-p3-runtime/wasi-random-list-lift-arc.core.wat"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-wasi-random-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

tool_version=$("$wasm_tools_bin" --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac

if [[ ! -x "$runner_cc" ]]; then
  printf 'missing Rust runner linker: %s\n' "$runner_cc" >&2
  exit 1
fi

"$zig_bin" run "$probe" -- "$tmp_dir/gc.core.wat" "$repo_root"
cp "$arc_core" "$tmp_dir/arc.core.wat"

for name in gc arc; do
  "$wasm_tools_bin" parse "$tmp_dir/$name.core.wat" -o "$tmp_dir/$name.core.wasm"
  "$wasm_tools_bin" component embed "$wit_dir" "$tmp_dir/$name.core.wasm" --world probe -o "$tmp_dir/$name.embedded.wasm"
  "$wasm_tools_bin" component new "$tmp_dir/$name.embedded.wasm" -o "$tmp_dir/$name.component.wasm"
  "$wasm_tools_bin" validate "$tmp_dir/$name.component.wasm"
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
