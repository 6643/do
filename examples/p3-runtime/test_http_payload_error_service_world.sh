#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
pinned_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16"
core_wat="$repo_root/examples/p3-runtime/http-payload-error-service-world.wat"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-http-payload-error-service-world.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
mkdir -p "$wit_dir"
cp -R "$pinned_wit/deps" "$wit_dir/"
cp "$pinned_wit/deps.toml" "$wit_dir/"
cp "$pinned_wit/deps.lock" "$wit_dir/"
cp "$pinned_wit"/*.wit "$wit_dir/"

for case_name in internal-error-none internal-error-some; do
  candidate_wat="$tmp_dir/$case_name.wat"
  candidate_wasm="$tmp_dir/$case_name.wasm"
  embedded="$tmp_dir/$case_name.embedded.wasm"
  component="$tmp_dir/$case_name.component.wasm"
  cp "$core_wat" "$candidate_wat"
  if [[ "$case_name" == internal-error-none ]]; then
    perl -0pi -e 's/i32\.const 38\n    i32\.const 1\n    i64\.const 512\n    i32\.const 1/i32.const 38\n    i32.const 0\n    i64.const 0\n    i32.const 0/' "$candidate_wat"
  fi
  wasm-tools parse "$candidate_wat" -o "$candidate_wasm"
  wasm-tools component embed "$wit_dir" "$candidate_wasm" --world service -o "$embedded"
  wasm-tools component new "$embedded" -o "$component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$component"
  for delivery in pending ready; do
    output=$(cd "$runner_dir" && \
      CC="$PWD/zig-cc.sh" CXX="$PWD/zig-cc.sh" \
      CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
      cargo run --quiet --bin do-p3-http-payload-error-abi-host-runner -- \
      "$component" service-probe "$case_name" "$delivery")
    expected='InternalError(None)'
    if [[ "$case_name" == internal-error-some ]]; then
      expected='InternalError(Some("x"))'
    fi
    grep -Fq "service-probe-gate=green delivery=$delivery case=$case_name observation=$expected" <<<"$output"
    grep -Fq 'table-empty=true' <<<"$output"
  done
done

printf 'WASI HTTP service-world payload error probe passed\n'
