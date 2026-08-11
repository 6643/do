#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-open-at.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-open-at-cancel.wit"
upstream_wit="$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-open-at.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-open-at-cancel.core.wat"
fixture="$repo_root/src/build/test/compile_ok/540_wasi_filesystem_open_at_component.do"
runner_source="$runner_dir/src/bin/wasi_filesystem_open_at.rs"
wasm_tools=${WASM_TOOLS:-wasm-tools}
expected_wasm_tools='wasm-tools 1.255.0 (76e20611d 2026-07-30)'
expected_wasm_tools_sha256=6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013
expected_upstream_sha256=8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f

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
[[ "$(sha256sum "$upstream_wit" | awk '{print $1}')" == "$expected_upstream_sha256" ]] || {
  printf 'pinned filesystem WIT source hash changed\n' >&2
  exit 1
}

for path in "$wit" "$cancel_wit" "$upstream_wit" "$core_wat" "$cancel_core_wat" "$fixture" "$runner_source"; do
  [[ -f "$path" ]] || {
    printf 'missing open-at runtime input: %s\n' "$path" >&2
    exit 1
  }
done

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-open-at-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/regular" "$tmp_dir/cancel" "$tmp_dir/generated-wit" "$tmp_dir/root"
cp "$wit" "$tmp_dir/regular/wasi-filesystem-open-at.wit"
cp "$cancel_wit" "$tmp_dir/cancel/wasi-filesystem-open-at-cancel.wit"
printf 'd2-open-at-file\n' >"$tmp_dir/root/file"
printf 'd2-open-at-utf8-file\n' >"$tmp_dir/root/é-file"

generated_wit="$tmp_dir/generated.wit"
generated_core_wat="$tmp_dir/generated.core.wat"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-output "$generated_wit" \
  -o "$generated_core_wat" >/dev/null
cp "$generated_wit" "$tmp_dir/generated-wit/generated.wit"

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

component=$(build_component "$tmp_dir/regular" open-at-probe "$core_wat" open-at)
cancel_component=$(build_component "$tmp_dir/cancel" open-at-cancel-probe "$cancel_core_wat" open-at-cancel)
generated_component=$(build_component "$tmp_dir/generated-wit" open-at-probe "$generated_core_wat" generated)

rustfmt --edition 2024 --check "$runner_source"

runner_env=(
  DO_D2_FILESYSTEM_ROOT="$tmp_dir/root"
  DO_D2_FILESYSTEM_PATH=file
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

run_runner() {
  local component_path="$1"
  local mode="$2"
  (cd "$runner_dir" && env "${runner_env[@]}" timeout 60s \
    cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin wasi-filesystem-open-at -- "$component_path" "$mode")
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

grep -Fq 'mode=ready result=Ok host-calls=1 path-copies=1 observed-path=file completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 parent-drops=1 child-drops=1 table-empty=true' <<<"$ready"
grep -Fq 'mode=pending result=Ok host-calls=1 path-copies=1 observed-path=é-file completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 parent-drops=1 child-drops=1 table-empty=true' <<<"$pending"
grep -Fq 'mode=error result=Err(no-entry) host-calls=1 path-copies=1 observed-path=missing-file completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 parent-drops=1 child-drops=0 table-empty=true' <<<"$error"
grep -Fq 'mode=cancel result=cancelled host-calls=1 path-copies=1 observed-path=<none> completion-polls=1 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 parent-drops=1 child-drops=0 table-empty=true' <<<"$cancel"
grep -Fq 'mode=early-drop result=store-discarded host-calls=1 path-copies=1 observed-path=<none> completion-polls=2 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 parent-drops=0 child-drops=0 table-empty=not-applicable' <<<"$early_drop"
grep -Fq 'mode=repeat results=Ok,Ok host-calls=2 path-copies=2 observed-path=file completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 parent-drops=2 child-drops=2 table-empty=true' <<<"$repeat"
grep -Fq 'mode=ready result=Ok host-calls=1 path-copies=1 observed-path=file completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 parent-drops=1 child-drops=1 table-empty=true' <<<"$generated_ready"
grep -Fq 'mode=pending result=Ok host-calls=1 path-copies=1 observed-path=é-file completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 parent-drops=1 child-drops=1 table-empty=true' <<<"$generated_pending"
grep -Fq 'mode=error result=Err(no-entry) host-calls=1 path-copies=1 observed-path=missing-file completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 parent-drops=1 child-drops=0 table-empty=true' <<<"$generated_error"
grep -Fq 'mode=repeat results=Ok,Ok host-calls=2 path-copies=2 observed-path=file completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 parent-drops=2 child-drops=2 table-empty=true' <<<"$generated_repeat"

printf 'D2 filesystem descriptor.open-at Rust/Wasmtime runtime passed\n'
printf 'modes=ready,pending,error,cancel,early-drop,repeat generated=ready,pending,error,repeat\n'
