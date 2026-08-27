#!/usr/bin/env bash
set -euo pipefail
# Verification Status: verified

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-$repo_root/bin/do}
wasm_tools_bin=${WASM_TOOLS_BIN:-$(command -v wasm-tools || true)}
wasmtime_bin=${WASMTIME_BIN:-/home/_/Public/wasmtime/bin/wasmtime}
cargo_bin=${CARGO_BIN:-cargo}
fixture="$repo_root/examples/p3-runtime/two-await-component.do"
linear_core="$repo_root/examples/gc-p3-runtime/async-frame-linear-oracle.wat"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-gc-async-frame-equivalence.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

if [[ ! -x "$do_bin" ]]; then
  printf 'missing do compiler: %s\n' "$do_bin" >&2
  exit 1
fi
if [[ -z "$wasm_tools_bin" || ! -x "$wasm_tools_bin" ]]; then
  printf 'missing wasm-tools executable\n' >&2
  exit 1
fi
if [[ ! -x "$wasmtime_bin" ]]; then
  printf 'missing Wasmtime executable: %s\n' "$wasmtime_bin" >&2
  exit 1
fi
if [[ ! -f "$linear_core" ]]; then
  printf 'missing linear async-frame oracle: %s\n' "$linear_core" >&2
  exit 1
fi
if ! command -v cc >/dev/null 2>&1; then
  if ! command -v zig >/dev/null 2>&1; then
    printf 'missing C linker: install cc or make zig available\n' >&2
    exit 1
  fi
  export CC="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

expected_wasm_tools='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
actual_wasm_tools=$($wasm_tools_bin --version)
if [[ "$actual_wasm_tools" != "$expected_wasm_tools" ]]; then
  printf 'unexpected wasm-tools version: expected %s, got %s\n' \
    "$expected_wasm_tools" "$actual_wasm_tools" >&2
  exit 1
fi

build_gc_component() {
  local wat="$tmp_dir/gc.wat" wit="$tmp_dir/gc.wit" embedded="$tmp_dir/gc.embedded.wasm" component="$tmp_dir/gc.component.wasm"
  DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
    --p3-wait-for-component --p3-wit-output "$wit" -o "$wat" >/dev/null
  if grep -Fq '__arc_' "$wat"; then
    printf 'generated GC frame output contains ARC markers\n' >&2
    exit 1
  fi
  for marker in '(type $async-frame (struct' '(table $async-frames 0 (ref null $async-frame))' 'table.get $async-frames'; do
    if ! grep -Fq "$marker" "$wat"; then
      printf 'generated GC frame output is missing marker: %s\n' "$marker" >&2
      exit 1
    fi
  done
  "$wasm_tools_bin" parse "$wat" -o "$tmp_dir/gc.core.wasm" >/dev/null
  "$wasm_tools_bin" component embed "$wit" "$wat" --world probe -o "$embedded"
  "$wasm_tools_bin" component new "$embedded" -o "$component"
  "$wasm_tools_bin" validate "$component"
  printf '%s\n' "$component"
}

build_linear_component() {
  local wit="$tmp_dir/gc.wit" embedded="$tmp_dir/linear.embedded.wasm" component="$tmp_dir/linear.component.wasm"
  "$wasm_tools_bin" parse "$linear_core" -o "$tmp_dir/linear.core.wasm" >/dev/null
  "$wasm_tools_bin" component embed "$wit" "$linear_core" --world probe -o "$embedded"
  "$wasm_tools_bin" component new "$embedded" -o "$component"
  "$wasm_tools_bin" validate "$component"
  printf '%s\n' "$component"
}

run_runner() {
  local component="$1" output="$2"
  "$cargo_bin" run --quiet --manifest-path "$runner_manifest" \
    --bin do-p3-two-await-host-runner -- "$component" >"$output"
  for marker in \
    'Rust P3 two-await adapter passed' \
    'clock parallel-calls=2' \
    'clock pending-polls=4' \
    'clock external-wakes=4' \
    'clock completions=4'; do
    if ! grep -Fq "$marker" "$output"; then
      printf 'missing two-await runner marker: %s\n' "$marker" >&2
      cat "$output" >&2
      exit 1
    fi
  done
}

gc_component=$(build_gc_component)
linear_component=$(build_linear_component)
run_runner "$gc_component" "$tmp_dir/gc.runner.out"
run_runner "$linear_component" "$tmp_dir/linear.runner.out"

for marker in \
  'clock parallel-calls=2' \
  'clock pending-polls=4' \
  'clock external-wakes=4' \
  'clock completions=4'; do
  gc_line=$(grep -F "$marker" "$tmp_dir/gc.runner.out")
  linear_line=$(grep -F "$marker" "$tmp_dir/linear.runner.out")
  if [[ "$gc_line" != "$linear_line" ]]; then
    printf 'GC/linear async-frame mismatch: gc=%s linear=%s\n' "$gc_line" "$linear_line" >&2
    exit 1
  fi
done

printf 'GC/linear Future frame equivalence passed rows=1 pending-polls=4 external-wakes=4 completions=4 wasm-tools=%s\n' "$actual_wasm_tools"
