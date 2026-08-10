#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-sync-data.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-sync-data.core.wat"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-sync-data-cancel.wit"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-sync-data-cancel.core.wat"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-sync-data-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

root="$tmp_dir/root"
mkdir -p "$root"
printf 'd2-sync\n' >"$root/file"

core_wasm="$tmp_dir/sync.core.wasm"
embedded="$tmp_dir/sync.embedded.wasm"
component="$tmp_dir/sync.component.wasm"
cancel_core_wasm="$tmp_dir/sync-cancel.core.wasm"
cancel_embedded="$tmp_dir/sync-cancel.embedded.wasm"
cancel_component="$tmp_dir/sync-cancel.component.wasm"
generated_wit="$tmp_dir/generated.wit"
generated_core_wat="$tmp_dir/generated.core.wat"
generated_core_wasm="$tmp_dir/generated.core.wasm"
generated_embedded="$tmp_dir/generated.embedded.wasm"
generated_component="$tmp_dir/generated.component.wasm"
wasm_tools=${WASM_TOOLS:-wasm-tools}

"$wasm_tools" parse "$core_wat" -o "$core_wasm"
"$wasm_tools" component embed "$wit" "$core_wasm" \
  --world sync-data-probe --features cm-async,cm-more-async-builtins -o "$embedded"
"$wasm_tools" component new --skip-validation "$embedded" -o "$component"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"

"$wasm_tools" parse "$cancel_core_wat" -o "$cancel_core_wasm"
"$wasm_tools" component embed "$cancel_wit" "$cancel_core_wasm" \
  --world sync-data-cancel-probe --features cm-async,cm-more-async-builtins -o "$cancel_embedded"
"$wasm_tools" component new --skip-validation "$cancel_embedded" -o "$cancel_component"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$cancel_component"

"$repo_root/bin/do" build "$repo_root/src/build/test/compile_ok/511_wasi_filesystem_sync_data_component.do" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_core_wat"
"$wasm_tools" parse "$generated_core_wat" -o "$generated_core_wasm"
"$wasm_tools" component embed "$generated_wit" "$generated_core_wasm" \
  --world sync-data-probe --features cm-async,cm-more-async-builtins -o "$generated_embedded"
"$wasm_tools" component new --skip-validation "$generated_embedded" -o "$generated_component"
"$wasm_tools" validate --features cm-async,cm-more-async-builtins "$generated_component"
grep -Fq 'package wasi:filesystem@0.3.0-rc-2025-09-16;' "$generated_wit"
grep -Fq 'sync-data: async func()' "$generated_wit"
grep -Fq 'run: async func(file: own<descriptor>)' "$generated_wit"
grep -Fq '"[async-lower][method]descriptor.sync-data"' "$generated_core_wat"
grep -Fq '"[resource-drop]descriptor"' "$generated_core_wat"

runner_source="$runner_dir/src/bin/wasi_filesystem_sync_data.rs"
rustfmt --edition 2024 --check "$runner_source"

runner_env=(
  DO_D2_FILESYSTEM_ROOT="$root"
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

run_runner() {
  local mode="$1"
  local runner_component="$component"
  if [[ "$mode" == cancel ]]; then
    runner_component="$cancel_component"
  fi
  run_runner_component "$runner_component" "$mode"
}

run_runner_component() {
  local runner_component="$1"
  local mode="$2"
  (cd "$runner_dir" && env "${runner_env[@]}" timeout 60s \
    cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-wasi-filesystem-sync-data-host-runner -- "$runner_component" "$mode")
}

ready=$(run_runner ready)
pending=$(run_runner pending)
error=$(run_runner error)
cancel=$(run_runner cancel)
early_drop=$(run_runner early-drop)
repeat=$(run_runner repeat)
generated_ready=$(run_runner_component "$generated_component" ready)
generated_pending=$(run_runner_component "$generated_component" pending)
generated_error=$(run_runner_component "$generated_component" error)
generated_repeat=$(run_runner_component "$generated_component" repeat)

grep -Fq 'mode=ready result=Ok host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$ready"
grep -Fq 'mode=pending result=Ok host-calls=1 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$pending"
grep -Fq 'mode=error result=Err(no-entry) host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$error"
grep -Fq 'mode=cancel result=cancelled host-calls=1 completion-polls=1 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=1 table-empty=true' <<<"$cancel"
grep -Fq 'mode=early-drop result=store-discarded host-calls=1 completion-polls=2 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=0 table-empty=not-applicable' <<<"$early_drop"
grep -Fq 'mode=repeat results=Ok,Ok host-calls=2 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 table-empty=true' <<<"$repeat"
grep -Fq 'mode=ready result=Ok host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$generated_ready"
grep -Fq 'mode=pending result=Ok host-calls=1 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$generated_pending"
grep -Fq 'mode=error result=Err(no-entry) host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$generated_error"
grep -Fq 'mode=repeat results=Ok,Ok host-calls=2 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 table-empty=true' <<<"$generated_repeat"

printf 'D2 filesystem descriptor.sync-data Rust/Wasmtime runtime passed\n'
