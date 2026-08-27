#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wasm_tools_bin=${WASM_TOOLS_BIN:-wasm-tools}
zig_bin=${ZIG_BIN:-zig}
cargo_bin=${CARGO_BIN:-cargo}
runner_cc=${RUST_RUNNER_CC:-$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh}
cc_bin=${CC:-$runner_cc}
cxx_bin=${CXX:-$runner_cc}
linker_bin=${CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER:-$runner_cc}
do_bin=$repo_root/bin/do
input_do=$repo_root/src/build/test/compile_ok/565_gc_wit_managed_record_host_boundary.do
wit=$repo_root/examples/gc-p3-runtime/marshal-record-managed-lower-assembly.wit
runner_manifest=$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-marshal-record-managed-lower-compiler-host.XXXXXX")
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

(
  cd "$repo_root/src"
  "$zig_bin" build -Doptimize=Debug
)

"$do_bin" build "$input_do" \
  --gc-wit-marshal demo:marshal-record-managed-lower/api.write@1.0.0/lower \
  -o "$tmp_dir/core.wat"

"$wasm_tools_bin" parse "$tmp_dir/core.wat" -o "$tmp_dir/core.wasm"
rg -q '\(type \$canonical_lower \(func \(param i32 i32 i32\)\)\)' "$tmp_dir/core.wat"
rg -q '\(import "demo:marshal-record-managed-lower/api@1.0.0" "write"' "$tmp_dir/core.wat"
if rg -q '^\s*\(import.*\(ref' "$tmp_dir/core.wat"; then
  printf 'GC reference crossed canonical managed-field record lower import\n' >&2
  exit 1
fi
rg -q 'array.get_s \$do_bytes' "$tmp_dir/core.wat"
rg -q 'struct.new \$do_record' "$tmp_dir/core.wat"
call_line=$(rg -n 'call \$canonical_call' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
free_line=$(rg -n 'call \$cabi_realloc' "$tmp_dir/core.wat" | tail -1 | cut -d: -f1)
if [ -z "$call_line" ] || [ -z "$free_line" ] || [ "$call_line" -ge "$free_line" ]; then
  printf 'managed-field lower call/free order is invalid\n' >&2
  exit 1
fi

"$wasm_tools_bin" component embed "$wit" "$tmp_dir/core.wasm" --world probe -o "$tmp_dir/embedded.wasm"
"$wasm_tools_bin" component new "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
"$wasm_tools_bin" validate "$tmp_dir/component.wasm"
"$wasm_tools_bin" component wit "$tmp_dir/component.wasm" > "$tmp_dir/component.wit"

output=$(
  CC="$cc_bin" CXX="$cxx_bin" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker_bin" \
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-gc-marshal-record-managed-lower-host-runner -- "$tmp_dir/component.wasm"
)
grep -Fq 'GC managed-field record lower host adapter passed code=7 label=hello write-calls=1 allocations=1 frees=1' <<<"$output"
printf '%s\n' "$output"
printf 'compiler-wired managed-field record lower Component host execution passed\n'
