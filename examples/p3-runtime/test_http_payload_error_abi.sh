#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
pinned_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16"
probe_fragment="$repo_root/examples/p3-runtime/wit/http-payload-error-probe.wit"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-http-payload-error-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
mkdir -p "$wit_dir"
cp -R "$pinned_wit/deps" "$wit_dir/"
cp "$pinned_wit/deps.toml" "$wit_dir/"
cp "$pinned_wit/deps.lock" "$wit_dir/"
cp "$pinned_wit"/*.wit "$wit_dir/"
cat "$probe_fragment" >>"$wit_dir/worlds.wit"

for candidate in canonical host-lowered; do
  core_wat="$repo_root/examples/p3-runtime/http-payload-error-$candidate.wat"
  core_wasm="$tmp_dir/$candidate.wasm"
  embedded="$tmp_dir/$candidate.embedded.wasm"
  component="$tmp_dir/$candidate.component.wasm"
  component_wit="$tmp_dir/$candidate.component.wit"

  wasm-tools parse "$core_wat" -o "$core_wasm"
  wasm-tools component embed "$wit_dir" "$core_wasm" \
    --world http-payload-error-probe -o "$embedded"
  wasm-tools component new "$embedded" -o "$component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$component"
  wasm-tools component wit "$component" >"$component_wit"

  grep -Fq 'import wasi:http/types@0.3.0-rc-2025-09-16;' "$component_wit"
  grep -Fq 'import wasi:http/client@0.3.0-rc-2025-09-16;' "$component_wit"
  grep -Fq 'export wasi:http/probe@0.3.0-rc-2025-09-16;' "$component_wit"
done

if [[ ${1:-} == --assemble-only ]]; then
  printf 'WASI HTTP payload error ABI assembly passed\n'
  exit 0
fi

runner_bin="$runner_dir/target/debug/do-p3-http-payload-error-abi-host-runner"
if [[ ! -x "$runner_bin" ]]; then
  printf 'runner-not-built\n' >&2
  exit 3
fi

printf 'assembly passed; runner integration is implemented in Task 2\n'
