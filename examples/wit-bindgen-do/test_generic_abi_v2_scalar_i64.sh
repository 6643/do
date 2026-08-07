#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../.." && pwd -P)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source_wit="$repo_root/examples/p3-runtime/wit/generic-async-scalar-i64-probe.wit"
source_main="$script_dir/project/scalar_i64_async_main.do"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
scalar_target=${DO_GENERIC_ABI_V2_SCALAR_TARGET:---p3-async-v2-scalar-i64}
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-generic-abi-v2-scalar-i64.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/wit"
cp "$source_main" "$tmp_dir/scalar_i64_async_main.do"

"$do_bin" wit check "$source_wit" --world probe
"$do_bin" wit bind "$source_wit" --world probe --out "$tmp_dir/wit"
"$do_bin" wit check "$source_wit" --world probe --manifest "$tmp_dir/wit/manifest.json"
"$do_bin" build "$tmp_dir/scalar_i64_async_main.do" \
  "$scalar_target" --p3-wit-output "$tmp_dir/generated.wit" \
  -o "$tmp_dir/runtime.wat"

cmp "$source_wit" "$tmp_dir/generated.wit"
grep -Fq 'generic ABI v2 independent scalar-i64 emitter template' "$tmp_dir/runtime.wat"
grep -Fq 'do:generic-async-scalar-i64-probe/host@0.1.0' "$tmp_dir/runtime.wat"
grep -Fq '[scalar-payload] offset=16 byte-size=8 alignment=8 encoding=core-s64' "$tmp_dir/runtime.wat"
grep -Fq 'i64.load' "$tmp_dir/runtime.wat"
grep -Fq 'i64.store' "$tmp_dir/runtime.wat"

wasm-tools parse "$tmp_dir/runtime.wat" -o "$tmp_dir/runtime.core.wasm"
wasm-tools component embed "$source_wit" "$tmp_dir/runtime.core.wasm" --world probe -o "$tmp_dir/embedded.wasm"
wasm-tools component new "$tmp_dir/embedded.wasm" -o "$tmp_dir/component.wasm"
wasm-tools validate --features cm-async,cm-more-async-builtins "$tmp_dir/component.wasm"

if ! command -v cc >/dev/null 2>&1; then
  export CC="$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh"
  export CXX="$CC"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$CC"
fi

run_mode() {
  local mode="$1"
  shift
  DO_GENERIC_ASYNC_SCALAR_MODE="$mode" cargo run --quiet --locked \
    --manifest-path "$runner_manifest" \
    --bin do-p3-generated-async-scalar-i64-host-runner -- "$tmp_dir/component.wasm"
}

ready_output=$(run_mode ready)
grep -Fq 'mode=ready value=42 polls=2 wakes=0 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true' <<<"$ready_output"
pending_output=$(run_mode pending)
grep -Fq 'mode=pending value=42 polls=3 wakes=1 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true' <<<"$pending_output"
cancel_output=$(run_mode cancel)
grep -Fq 'mode=cancel value=42 polls=3 wakes=0 completions=1 future-drops=2 pending-future-drops=1 frame-drops=1 table-empty=true' <<<"$cancel_output"

manifest="$tmp_dir/wit/manifest.json"
sed -i 's/"offset":16/"offset":24/' "$manifest"
if "$do_bin" build "$tmp_dir/scalar_i64_async_main.do" "$scalar_target" -o "$tmp_dir/mutated.wat" >"$tmp_dir/mutated.stdout" 2>"$tmp_dir/mutated.stderr"; then
  printf 'expected i64 payload mutation to fail closed\n' >&2
  exit 1
fi
test ! -e "$tmp_dir/mutated.wat"
grep -Fq 'GeneratedWitManifestMismatch' "$tmp_dir/mutated.stderr"

printf 'generic ABI v2 scalar-i64 Component/Rust/Wasmtime gate: PASS\n'
