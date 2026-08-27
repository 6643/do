#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
wit="$repo_root/examples/gc-p3-runtime/marshal-record-managed-lower-assembly.wit"
probe="$repo_root/src/gc_marshal_record_managed_lower_probe_main.zig"
arc_core_wat="$repo_root/examples/gc-p3-runtime/marshal-record-managed-lower-arc.core.wat"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-managed-lower-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

tool_version=$($wasm_tools_bin --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac
if [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Rust runner linker\n' >&2
  exit 1
fi

"$zig_bin" run "$probe" -- "$tmp_dir/gc.core.wat" "$repo_root"
"$wasm_tools_bin" parse "$tmp_dir/gc.core.wat" -o "$tmp_dir/gc.core.wasm"
"$wasm_tools_bin" parse "$arc_core_wat" -o "$tmp_dir/arc.core.wasm"
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/gc.core.wat" "$arc_core_wat"; then
  printf 'GC reference crossed canonical managed-field record lower import\n' >&2
  exit 1
fi
"$wasm_tools_bin" component embed "$wit" "$tmp_dir/gc.core.wasm" --world probe -o "$tmp_dir/gc.embedded.wasm"
"$wasm_tools_bin" component embed "$wit" "$tmp_dir/arc.core.wasm" --world probe -o "$tmp_dir/arc.embedded.wasm"
"$wasm_tools_bin" component new "$tmp_dir/gc.embedded.wasm" -o "$tmp_dir/gc.component.wasm"
"$wasm_tools_bin" component new "$tmp_dir/arc.embedded.wasm" -o "$tmp_dir/arc.component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/gc.component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/arc.component.wasm"

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-managed-lower-host-equivalence-runner -- \
    "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/ARC managed-field record lower equivalence passed code=7 label=hello allocations=1/1 frees=1/1 write-calls=1/1' <<<"$output"
printf '%s\n' "$output"

printf 'manifest-backed managed-field record lower ARC/GC equivalence passed\n'
