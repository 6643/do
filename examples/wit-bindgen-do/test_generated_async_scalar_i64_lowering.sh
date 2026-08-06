#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../.." && pwd -P)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
source_wit="$repo_root/examples/p3-runtime/wit/generic-async-scalar-i64-probe.wit"
source_main="$script_dir/project/scalar_i64_async_main.do"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "$repo_root/.tmp/wit-generated-async-scalar-i64.XXXXXX")

mkdir -p "$tmp_dir/wit"
cp "$source_main" "$tmp_dir/scalar_i64_async_main.do"

"$do_bin" wit check "$source_wit" --world probe
"$do_bin" wit bind "$source_wit" --world probe --out "$tmp_dir/wit"
"$do_bin" wit check "$source_wit" --world probe --manifest "$tmp_dir/wit/manifest.json"
"$do_bin" build "$tmp_dir/scalar_i64_async_main.do" \
  --p3-async-component --p3-wit-output "$tmp_dir/generated.wit" \
  -o "$tmp_dir/runtime.wat"

cmp "$source_wit" "$tmp_dir/generated.wit"
grep -Fq 'do:generic-async-scalar-i64-probe/host@0.1.0' "$tmp_dir/runtime.wat"
grep -Fq '[scalar-payload] offset=16 byte-size=8 alignment=8 encoding=core-s64' "$tmp_dir/runtime.wat"
grep -Fq 'i64.load' "$tmp_dir/runtime.wat"
grep -Fq 'i64.store' "$tmp_dir/runtime.wat"
grep -Fq 'i64.const 0' "$tmp_dir/runtime.wat"

core_wasm="$tmp_dir/runtime.core.wasm"
embedded="$tmp_dir/runtime.embedded.wasm"
component="$tmp_dir/runtime.component.wasm"
wasm-tools parse "$tmp_dir/runtime.wat" -o "$core_wasm"
wasm-tools component embed "$source_wit" "$core_wasm" --world probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

cargo_bin=${CARGO_BIN:-cargo}
if ! command -v cc >/dev/null && command -v zig >/dev/null; then
  export CC="$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$CC"
fi

run_runner() {
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-generated-async-scalar-i64-host-runner -- "$component"
}

ready_output=$(DO_GENERIC_ASYNC_SCALAR_MODE=ready run_runner)
grep -Fq 'mode=ready value=42 polls=2 wakes=0 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true' <<<"$ready_output"

pending_output=$(DO_GENERIC_ASYNC_SCALAR_MODE=pending run_runner)
grep -Fq 'mode=pending value=42 polls=3 wakes=1 completions=2 future-drops=2 pending-future-drops=0 frame-drops=1 table-empty=true' <<<"$pending_output"

cancel_output=$(DO_GENERIC_ASYNC_SCALAR_MODE=cancel run_runner)
grep -Fq 'mode=cancel value=42 polls=3 wakes=0 completions=1 future-drops=2 pending-future-drops=1 frame-drops=1 table-empty=true' <<<"$cancel_output"

manifest="$tmp_dir/wit/manifest.json"
cp "$manifest" "$tmp_dir/manifest.original"
sed -i 's/"offset":16/"offset":24/' "$manifest"
if "$do_bin" build "$tmp_dir/scalar_i64_async_main.do" --p3-async-component -o "$tmp_dir/mutated.wat" >"$tmp_dir/mutated.stdout" 2>"$tmp_dir/mutated.stderr"; then
  printf 'expected i64 payload mutation to fail closed\n' >&2
  exit 1
fi
test ! -e "$tmp_dir/mutated.wat"
grep -Fq 'GeneratedWitManifestMismatch' "$tmp_dir/mutated.stderr"

printf 'generated async scalar i64 Component/Rust/Wasmtime gate: PASS\n'
