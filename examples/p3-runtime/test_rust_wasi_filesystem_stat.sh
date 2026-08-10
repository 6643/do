#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-stat.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-stat-cancel.wit"
clock_wit="$repo_root/examples/p3-runtime/wit/wasi-clocks-wall-clock.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-stat.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-stat-cancel.core.wat"
fixture="$repo_root/src/build/test/compile_ok/498_wasi_filesystem_stat_component.do"
wasm_tools=${WASM_TOOLS:-wasm-tools}
expected_wasm_tools='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
expected_wasm_tools_sha256=6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013

command -v "$wasm_tools" >/dev/null || {
  printf 'missing executable: %s\n' "$wasm_tools" >&2
  exit 1
}
[[ "$($wasm_tools --version)" == "$expected_wasm_tools" ]] || {
  printf 'wasm-tools version mismatch\n' >&2
  exit 1
}
[[ "$(sha256sum "$(command -v "$wasm_tools")" | awk '{print $1}')" == "$expected_wasm_tools_sha256" ]] || {
  printf 'wasm-tools hash mismatch\n' >&2
  exit 1
}

for path in "$wit" "$cancel_wit" "$clock_wit" "$core_wat" "$cancel_core_wat"; do
  [[ -f "$path" ]] || {
    printf 'missing stat runtime input: %s\n' "$path" >&2
    exit 1
  }
done

runner_source="$runner_dir/src/bin/do-p3-wasi-filesystem-stat-host-runner.rs"
[[ -f "$runner_source" ]] || {
  printf 'missing stat Rust oracle: %s\n' "$runner_source" >&2
  exit 1
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-stat-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/regular/deps/clocks" "$tmp_dir/cancel/deps/clocks" "$tmp_dir/root"
cp "$wit" "$tmp_dir/regular/wasi-filesystem-stat.wit"
cp "$cancel_wit" "$tmp_dir/cancel/wasi-filesystem-stat-cancel.wit"
cp "$clock_wit" "$tmp_dir/regular/deps/clocks/wall-clock.wit"
cp "$clock_wit" "$tmp_dir/cancel/deps/clocks/wall-clock.wit"
printf 'd2-stat-record\n' >"$tmp_dir/root/file"
mkdir "$tmp_dir/root/dir"

generated_wit="$tmp_dir/generated.wit"
generated_core_wat="$tmp_dir/generated.core.wat"
generated_wit_dir="$tmp_dir/generated-wit"
mkdir -p "$generated_wit_dir/deps/clocks"
"$repo_root/bin/do" build "$fixture" \
  --p3-wasi-filesystem-stat-component --p3-wit-output "$generated_wit" \
  -o "$generated_core_wat" >/dev/null
cp "$generated_wit" "$generated_wit_dir/generated.wit"
cp "$clock_wit" "$generated_wit_dir/deps/clocks/wall-clock.wit"

build_component() {
  local input_dir="$1"
  local world="$2"
  local wat="$3"
  local name="$4"
  local core="$tmp_dir/$name.core.wasm"
  local embedded="$tmp_dir/$name.embedded.wasm"
  local component="$tmp_dir/$name.component.wasm"
  "$wasm_tools" parse "$wat" -o "$core"
  "$wasm_tools" component embed "$input_dir" "$core" --world "$world" \
    --features cm-async,cm-more-async-builtins -o "$embedded"
  "$wasm_tools" component new --skip-validation "$embedded" -o "$component"
  "$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"
  printf '%s\n' "$component"
}

component=$(build_component "$tmp_dir/regular" stat-probe "$core_wat" stat)
cancel_component=$(build_component "$tmp_dir/cancel" stat-cancel-probe "$cancel_core_wat" stat-cancel)
generated_component=$(build_component "$generated_wit_dir" stat-probe "$generated_core_wat" generated)

rustfmt --edition 2024 --check "$runner_source"

runner_env=(
  DO_D2_FILESYSTEM_ROOT="$tmp_dir/root"
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

run_runner() {
  local component_path="$1"
  local mode="$2"
  (cd "$runner_dir" && env "${runner_env[@]}" timeout 60s \
    cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-wasi-filesystem-stat-host-runner -- "$component_path" "$mode")
}

ready=$(run_runner "$component" ready)
pending=$(run_runner "$component" pending)
error=$(run_runner "$component" error)
cancel=$(run_runner "$cancel_component" cancel)
early_drop=$(run_runner "$component" early-drop)
repeat=$(run_runner "$component" repeat)
generated_ready=$(run_runner "$generated_component" ready)
generated_pending=$(run_runner "$generated_component" pending)
generated_error=$(run_runner "$generated_component" error)
generated_repeat=$(run_runner "$generated_component" repeat)

grep -Fq 'mode=ready result=Ok descriptor-type=regular-file link-count=1 size=4096 access=Some(100,1) modification=Some(101,2) change=Some(102,3) host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$ready"
grep -Fq 'mode=pending result=Ok descriptor-type=regular-file link-count=1 size=4096 access=Some(100,1) modification=Some(101,2) change=Some(102,3) host-calls=1 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$pending"
grep -Fq 'mode=error result=Err(no-entry) options=none host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$error"
grep -Fq 'mode=cancel result=cancelled host-calls=1 completion-polls=1 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=1 table-empty=true' <<<"$cancel"
grep -Fq 'mode=early-drop result=store-discarded host-calls=1 completion-polls=2 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=0 table-empty=not-applicable' <<<"$early_drop"
grep -Fq 'mode=repeat results=Ok,Ok host-calls=2 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 table-empty=true' <<<"$repeat"
grep -Fq 'mode=ready result=Ok descriptor-type=regular-file link-count=1 size=4096 access=Some(100,1) modification=Some(101,2) change=Some(102,3) host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$generated_ready"
grep -Fq 'mode=pending result=Ok descriptor-type=regular-file link-count=1 size=4096 access=Some(100,1) modification=Some(101,2) change=Some(102,3) host-calls=1 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$generated_pending"
grep -Fq 'mode=error result=Err(no-entry) options=none host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$generated_error"
grep -Fq 'mode=repeat results=Ok,Ok host-calls=2 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 table-empty=true' <<<"$generated_repeat"

printf 'D2 filesystem descriptor.stat Rust/Wasmtime runtime passed\n'
printf 'generated-component-modes=ready,pending,error,repeat; cancel-and-early-drop=hand-authored-oracle\n'
