#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
fixture="$repo_root/examples/p3-runtime/http-response-status.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-response-status.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/status.wat"
wit="$tmp_dir/status.wit"
core_wasm="$tmp_dir/status.wasm"
embedded="$tmp_dir/status.embedded.wasm"
component="$tmp_dir/status.component.wasm"
component_wit="$tmp_dir/status.component.wit"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-output "$wit" -o "$core_wat"

grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[method]response.get-status-code"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]response"' "$core_wat"
grep -Fq '(func $run (param $response i32) (result i32)' "$core_wat"
grep -Fq 'get-status-code: func() -> u16' "$wit"
grep -Fq 'run: func(response: own<response>) -> u16' "$wit"

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" --world http-status-probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate "$component"
wasm-tools component wit "$component" > "$component_wit"

grep -Fq 'import wasi:http/types@0.3.0-rc-2025-09-16;' "$component_wit"
grep -Fq 'export wasi:http/probe@0.3.0-rc-2025-09-16;' "$component_wit"

output=$(cd "$repo_root/examples/p3-runtime/rust-host-runner" && \
  CC="$PWD/zig-cc.sh" CXX="$PWD/zig-cc.sh" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
  cargo run --quiet --bin do-p3-http-response-status-host-runner -- "$component")
for marker in 'Rust P3 HTTP response status adapter passed' 'status=27815' 'drop=1'; do
  case "$output" in
    *"$marker"*) ;;
    *) printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2; exit 1 ;;
  esac
done

printf 'WASI HTTP response status lowering passed\n'
