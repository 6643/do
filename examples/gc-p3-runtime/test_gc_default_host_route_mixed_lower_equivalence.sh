#!/usr/bin/env bash
# Verification Status: verified
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-mixed-lower-call.do
wit=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-lower-assembly.wit
arc_core_wat=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-lower-arc.core.wat
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-mixed-lower-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [ ! -x "$do_bin" ]; then
  printf 'missing do compiler executable: %s\n' "$do_bin" >&2
  exit 1
fi
tool_version=$($wasm_tools_bin --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac
if [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

# The GC side comes from the ordinary compiler route; the ARC side is the
# fixed linear-memory oracle for this exact descriptor.
"$do_bin" build "$input_do" -o "$tmp_dir/gc.core.wat"
awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 42)" }' \
  "$tmp_dir/gc.core.wat" > "$tmp_dir/gc.component.core.wat"
"$wasm_tools_bin" parse "$tmp_dir/gc.component.core.wat" -o "$tmp_dir/gc.core.wasm"
"$wasm_tools_bin" parse "$arc_core_wat" -o "$tmp_dir/arc.core.wasm"

rg -q '^  ;; gc-sync ' "$tmp_dir/gc.core.wat"
if rg -q '__arc_' "$tmp_dir/gc.core.wat"; then
  printf 'default mixed scalar lower equivalence route still contains ARC runtime symbols\n' >&2
  exit 1
fi
rg -q '\(type \$canonical_lower \(func \(param i32 i64 i64\)\)\)' "$tmp_dir/gc.core.wat"
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/gc.core.wat"; then
  printf 'GC reference crossed the mixed scalar lower canonical import\n' >&2
  exit 1
fi
if rg -q '^\s*\(import.*\(ref' "$arc_core_wat"; then
  printf 'ARC oracle canonical import unexpectedly carries a GC reference\n' >&2
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
    --bin gc_marshal_record_mixed_lower_equivalence -- \
    "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/flat mixed scalar record lower equivalence passed results=42/42 write-calls=1/1' <<<"$output"
printf '%s\n' "$output"
printf 'default mixed scalar record lower compiler/ARC equivalence passed\n'
