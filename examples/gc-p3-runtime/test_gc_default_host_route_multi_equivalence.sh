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
do_bin=$repo_root/bin/do
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-c15d-call.do
wit=$repo_root/examples/gc-p3-runtime/marshal-record-managed-lower-multi-assembly.wit
arc_core_wat=$repo_root/examples/gc-p3-runtime/marshal-record-managed-lower-multi-arc.core.wat
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-default-managed-lower-multi-equivalence.XXXXXX")
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

# The GC side is the ordinary route; the ARC side is the fixed oracle.
"$do_bin" build "$input_do" -o "$tmp_dir/gc.core.wat"
awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 34)" }' \
  "$tmp_dir/gc.core.wat" > "$tmp_dir/gc.component.core.wat"
"$wasm_tools_bin" parse "$tmp_dir/gc.component.core.wat" -o "$tmp_dir/gc.core.wasm"
"$wasm_tools_bin" parse "$arc_core_wat" -o "$tmp_dir/arc.core.wasm"
rg -q '^  ;; gc-sync ' "$tmp_dir/gc.core.wat"
if rg -q '__arc_' "$tmp_dir/gc.core.wat"; then
  printf 'default C15-D equivalence route still contains ARC runtime symbols\n' >&2
  exit 1
fi
rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$tmp_dir/gc.core.wat"
if rg -q '^\s*\(import "demo:marshal-record-managed-lower-multi/api@1.0.0" "write".*\(ref' "$tmp_dir/gc.core.wat"; then
  printf 'GC reference crossed the default C15-D canonical import\n' >&2
  exit 1
fi
test "$(rg -c 'array.get_s \$do_bytes' "$tmp_dir/gc.core.wat")" -eq 2
test "$(rg -c 'call \$cabi_realloc' "$tmp_dir/gc.core.wat")" -eq 4
gc_call_line=$(rg -n 'call \$__gc_canonical_call' "$tmp_dir/gc.core.wat" | tail -1 | cut -d: -f1)
gc_free_line=$(rg -n 'call \$cabi_realloc' "$tmp_dir/gc.core.wat" | tail -1 | cut -d: -f1)
if [ -z "$gc_call_line" ] || [ -z "$gc_free_line" ] || [ "$gc_call_line" -ge "$gc_free_line" ]; then
  printf 'default C15-D call/free order is invalid\n' >&2
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
    --bin do-p3-gc-marshal-record-managed-lower-multi-equivalence-runner -- \
    "$tmp_dir/gc.component.wasm" "$tmp_dir/arc.component.wasm"
)
grep -Fq 'GC/ARC multi-managed-field record lower equivalence passed code=7 label=hello note=world allocations=2/2 frees=2/2 write-calls=1/1' <<<"$output"
printf '%s\n' "$output"
printf 'default C15-D multi-managed-field record lower ARC/GC equivalence passed\n'

lift_input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-c16d-call.do
lift_wit=$repo_root/examples/gc-p3-runtime/marshal-record-managed-lift-multi-assembly.wit
lift_arc_core_wat=$repo_root/examples/gc-p3-runtime/marshal-record-managed-lift-multi-arc.core.wat

# The C16-D GC component also comes from ordinary compilation and is compared
# with its fixed linear-memory oracle.
"$do_bin" build "$lift_input_do" -o "$tmp_dir/lift.gc.core.wat"
awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 17)" }' \
  "$tmp_dir/lift.gc.core.wat" > "$tmp_dir/lift.gc.component.core.wat"
"$wasm_tools_bin" parse "$tmp_dir/lift.gc.component.core.wat" -o "$tmp_dir/lift.gc.core.wasm"
"$wasm_tools_bin" parse "$lift_arc_core_wat" -o "$tmp_dir/lift.arc.core.wasm"
rg -q '^  ;; gc-sync ' "$tmp_dir/lift.gc.core.wat"
if rg -q '__arc_' "$tmp_dir/lift.gc.core.wat"; then
  printf 'default C16-D equivalence route still contains ARC runtime symbols\n' >&2
  exit 1
fi
rg -q '\(type \$canonical_lift \(func \(param i32\)\)\)' "$tmp_dir/lift.gc.core.wat"
if rg -q '^\s*\(import "demo:marshal-record-managed-lift-multi/api@1.0.0" "read".*\(ref' "$tmp_dir/lift.gc.core.wat"; then
  printf 'GC reference crossed the default C16-D canonical import\n' >&2
  exit 1
fi

"$wasm_tools_bin" component embed "$lift_wit" "$tmp_dir/lift.gc.core.wasm" --world probe -o "$tmp_dir/lift.gc.embedded.wasm"
"$wasm_tools_bin" component embed "$lift_wit" "$tmp_dir/lift.arc.core.wasm" --world probe -o "$tmp_dir/lift.arc.embedded.wasm"
"$wasm_tools_bin" component new "$tmp_dir/lift.gc.embedded.wasm" -o "$tmp_dir/lift.gc.component.wasm"
"$wasm_tools_bin" component new "$tmp_dir/lift.arc.embedded.wasm" -o "$tmp_dir/lift.arc.component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/lift.gc.component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/lift.arc.component.wasm"

lift_output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-managed-lift-multi-host-equivalence-runner -- \
    "$tmp_dir/lift.gc.component.wasm" "$tmp_dir/lift.arc.component.wasm"
)
grep -Fq 'GC/ARC manifest managed multi-field record lift equivalence passed values=17/17' <<<"$lift_output"
printf '%s\n' "$lift_output"
printf 'default C16-D multi-managed-field record lift ARC/GC equivalence passed\n'
