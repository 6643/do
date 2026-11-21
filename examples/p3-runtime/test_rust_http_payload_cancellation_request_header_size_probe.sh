#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
runner_bin_dir="${CARGO_TARGET_DIR:-$runner_dir/target}/debug"
core_wat="$repo_root/examples/p3-runtime/http-payload-cancel-request-header-size-discard-probe.wat"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/http-payload-cancel-request-header-size.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wasm="$tmp_dir/http-payload-cancel-request-header-size.wasm"
embedded="$tmp_dir/http-payload-cancel-request-header-size.embedded.wasm"
component="$tmp_dir/http-payload-cancel-request-header-size.component.wasm"

test -x "$toolchain_bin"

cp -R "$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16" "$wit_dir"
cp "$repo_root/examples/p3-runtime/wit/http-payload-cancel-service-world.wit" \
  "$wit_dir/http-payload-cancel-service-world.wit"

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_dir" "$core_wasm" http-payload-cancel \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

CC="$runner_dir/zig-cc.sh" \
CXX="$runner_dir/zig-cc.sh" \
CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh" \
  cargo build --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin http_payload_cancel

output=$("$runner_bin_dir/http_payload_cancel" \
  "$component" ready-request-header-size --expect-request-header-size-discard)
for marker in \
  'Rust P3 HTTP payload cancellation probe passed' \
  'mode=ready-request-header-size' \
  'request consumed=1' \
  'pending future drops=0' \
  'ready future polls=1' \
  'ready future drops=1' \
  'response create=0' \
  'response drop=0' \
  'expected trap=false' \
  'table-empty=true'; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing request-header-size discard marker: %s\n%s\n' "$marker" "$output" >&2
      exit 1
      ;;
  esac
done

printf '%s\n' "$output"
printf 'WASI HTTP request-header-size cancellation discard probe passed\n'
