#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
do_bin=${DO_BIN:-$repo_root/bin/do}
input_do=$repo_root/examples/gc-p3-runtime/ordinary-host-record-mixed-text-u32-list-lift-call.do
descriptor=demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift
wit=$repo_root/examples/gc-p3-runtime/marshal-record-mixed-text-u32-list-lift-assembly.wit
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-mixed-text-u32-list-lift-host.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

tool_version=$($wasm_tools_bin --version)
case "$tool_version" in
  "wasm-tools 1.255.0 (76e20611d"*) ;;
  *) printf 'unexpected wasm-tools version: %s\n' "$tool_version" >&2; exit 1 ;;
esac
if [ ! -x "$wasmtime_bin" ] || [ ! -x "$cc_bin" ] || [ ! -x "$cxx_bin" ] || [ ! -x "$linker_bin" ]; then
  printf 'missing Wasmtime or Rust runner linker\n' >&2
  exit 1
fi

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$input_do" \
  --gc-wit-marshal "$descriptor" -o "$tmp_dir/core.wat"
"$wasm_tools_bin" parse "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"
rg -q '^  \(type \$canonical_lift \(func \(param i32\)\)\)' "$tmp_dir/core.wat"
rg -q '\(import "demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0" "read"' "$tmp_dir/core.wat"
if rg -q '__arc_' "$tmp_dir/core.wat"; then
  printf 'explicit mixed text/u32-list record lift route still contains ARC symbols\n' >&2
  exit 1
fi
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/core.wat"; then
  printf 'GC reference crossed canonical mixed text/u32-list record lift import\n' >&2
  exit 1
fi
rg -q 'array.new_default \$do_bytes' "$tmp_dir/core.wat"
rg -q 'array.new_default \$do_u32' "$tmp_dir/core.wat"
rg -q 'array.set \$do_bytes' "$tmp_dir/core.wat"
rg -q 'array.set \$do_u32' "$tmp_dir/core.wat"
rg -q 'struct.new \$do_record' "$tmp_dir/core.wat"
test "$(rg -c 'call \$cabi_realloc' "$tmp_dir/core.wat")" -eq 2
mapfile -t call_lines < <(rg -n 'call \$canonical_call|call \$cabi_realloc' "$tmp_dir/core.wat" | cut -d: -f1)
test "${#call_lines[@]}" -eq 3
if [ "${call_lines[0]}" -ge "${call_lines[1]}" ] || [ "${call_lines[1]}" -ge "${call_lines[2]}" ]; then
  printf 'mixed text/u32-list record lift call/free order is invalid\n' >&2
  exit 1
fi

"$wasm_tools_bin" component embed "$wit" "$tmp_dir/core.wasm" --world probe -o "$tmp_dir/embedded.wasm"
"$wasm_tools_bin" component new "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/component.wasm"

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-mixed-text-u32-list-lift-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC mixed text/u32-list record lift host adapter passed code=7 label=hello payload=[10, 20, 5] result=47 stats=34 read-calls=1 allocations=2 frees=2' <<<"$output"
printf '%s\n' "$output"
printf 'manifest-backed mixed text/u32-list record lift Component host execution passed\n'
