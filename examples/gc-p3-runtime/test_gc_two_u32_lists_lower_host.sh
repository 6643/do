#!/usr/bin/env bash
# Verification Status: pending
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
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-record-two-u32-lists-lower-call.do
wit=$repo_root/examples/gc-p3-runtime/marshal-record-two-u32-lists-lower-assembly.wit
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-two-u32-lists-lower-host.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

tool_version=$($wasm_tools_bin --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac
if [[ ! -x "$do_bin" || ! -x "$cc_bin" || ! -x "$cxx_bin" || ! -x "$linker_bin" ]]; then
  printf 'missing compiler or Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

"$do_bin" build "$input_do" -o "$tmp_dir/core.wat"
rg -q '^  ;; gc-sync ' "$tmp_dir/core.wat"
if rg -q '__arc_' "$tmp_dir/core.wat"; then
  printf 'two-u32-list lower route still contains ARC runtime symbols\n' >&2
  exit 1
fi
rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32 i32 i32\)\)\)' "$tmp_dir/core.wat"
rg -q '\(import "demo:marshal-record-two-u32-lists-lower/api@1.0.0" "write"' "$tmp_dir/core.wat"
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/core.wat"; then
  printf 'GC reference crossed two-u32-list lower canonical import\n' >&2
  exit 1
fi
test "$(rg -c 'array.get \$do_u32' "$tmp_dir/core.wat")" -eq 2
test "$(rg -c 'call \$cabi_realloc' "$tmp_dir/core.wat")" -eq 4
mapfile -t realloc_lines < <(rg -n 'call \$cabi_realloc' "$tmp_dir/core.wat" | cut -d: -f1)
call_line=$(rg -n 'call \$(__gc_)?canonical_call' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
if [[ -z "$call_line" || "$call_line" -ge "${realloc_lines[2]}" || "${realloc_lines[2]}" -ge "${realloc_lines[3]}" ]]; then
  printf 'two-u32-list lower canonical call/free order is invalid\n' >&2
  exit 1
fi

awk '{ print } /  \(export "_start" \(func \$_start\)\)/ { print "  (func (export \"run\") (result i32) call $_start i32.const 34)" }' \
  "$tmp_dir/core.wat" > "$tmp_dir/component.core.wat"
"$wasm_tools_bin" parse "$tmp_dir/component.core.wat" -o "$tmp_dir/core.wasm"
"$wasm_tools_bin" component embed "$wit" "$tmp_dir/core.wasm" --world probe -o "$tmp_dir/embedded.wasm"
"$wasm_tools_bin" component new "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/component.wasm"

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-two-u32-lists-lower-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC two-u32-list record lower host adapter passed code=7 first=[10, 20, 5] second=[3, 4] write-calls=1 allocations=2 frees=2' <<<"$output"
printf '%s\n' "$output"
printf 'two-u32-list record lower Component host execution passed\n'
