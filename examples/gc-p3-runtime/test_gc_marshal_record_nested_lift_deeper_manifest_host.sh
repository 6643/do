#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
wit="$repo_root/examples/gc-p3-runtime/marshal-record-nested-lift-deeper-assembly.wit"
probe="$repo_root/src/gc_marshal_record_nested_lift_deeper_probe_main.zig"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-nested-lift-deeper-host.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$wasmtime_bin" ] || [ ! -x "$toolchain_bin" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Wasmtime, do-toolchain, or Rust runner linker\n' >&2
  exit 1
fi

"$zig_bin" run "$probe" -- "$tmp_dir/core.wat" "$repo_root"
"$toolchain_bin" parse-core "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/core.wat"; then
  printf 'GC reference crossed canonical four-level nested lift import\n' >&2
  exit 1
fi
rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$tmp_dir/core.wat"
rg -q 'i32.const 32' "$tmp_dir/core.wat"
"$toolchain_bin" embed-component "$wit" "$tmp_dir/core.wasm" probe --features none -o "$tmp_dir/embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$toolchain_bin" validate-component "$tmp_dir/component.wasm" --features none

mutated_root="$tmp_dir/mutated-repository"
record_source_relative='examples/gc-p3-runtime/marshal-record-nested-lift-deeper-manifest-source.wit'
mkdir -p "$mutated_root/examples/gc-p3-runtime" "$mutated_root/doc/wit"
cp "$repo_root/$record_source_relative" "$mutated_root/$record_source_relative"
cp "$repo_root/doc/wit/gc_marshal_record_nested_lift_deeper_imports.wit" "$mutated_root/doc/wit/gc_marshal_record_nested_lift_deeper_imports.wit"
cp "$repo_root/doc/wit/gc_descriptor_manifest.json" "$mutated_root/doc/wit/gc_descriptor_manifest.json"
printf '\n' >> "$mutated_root/$record_source_relative"
if mutated_output=$($zig_bin run "$probe" -- "$tmp_dir/mutated.wat" "$mutated_root" 2>&1); then
  printf 'mutated descriptor source unexpectedly passed the manifest hash gate\n' >&2
  exit 1
fi
grep -Fq 'SourceHashMismatch' <<<"$mutated_output"

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-nested-lift-deeper-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC four-level nested scalar record lift host adapter passed sum=42' <<<"$output"
printf '%s\n' "$output"

printf 'manifest-backed four-level nested scalar record lift Component host execution passed\n'
