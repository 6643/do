#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-metadata-hash.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-metadata-hash-cancel.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-metadata-hash.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-metadata-hash-cancel.core.wat"
runner_source="$runner_dir/src/bin/wasi_filesystem_metadata_hash.rs"
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

for path in "$wit" "$cancel_wit" "$core_wat" "$cancel_core_wat" "$runner_source"; do
  [[ -f "$path" ]] || {
    printf 'missing metadata-hash runtime input: %s\n' "$path" >&2
    exit 1
  }
done

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-metadata-hash-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/regular" "$tmp_dir/cancel" "$tmp_dir/root"
cp "$wit" "$tmp_dir/regular/wasi-filesystem-metadata-hash.wit"
cp "$cancel_wit" "$tmp_dir/cancel/wasi-filesystem-metadata-hash-cancel.wit"
printf 'd2-metadata-hash\n' >"$tmp_dir/root/file"

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

component=$(build_component "$tmp_dir/regular" metadata-hash-probe "$core_wat" metadata-hash)
cancel_component=$(build_component "$tmp_dir/cancel" metadata-hash-cancel-probe "$cancel_core_wat" metadata-hash-cancel)

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
    --bin wasi-filesystem-metadata-hash -- "$component_path" "$mode")
}

ready=$(run_runner "$component" ready)
pending=$(run_runner "$component" pending)
error=$(run_runner "$component" error)
cancel=$(run_runner "$cancel_component" cancel)
early_drop=$(run_runner "$component" early-drop)
repeat=$(run_runner "$component" repeat)

grep -Fq 'mode=ready result=Ok lower=72623859790382856 upper=1230066625199609624 host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$ready"
grep -Fq 'mode=pending result=Ok lower=72623859790382856 upper=1230066625199609624 host-calls=1 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$pending"
grep -Fq 'mode=error result=Err(no-entry) host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$error"
grep -Fq 'mode=cancel result=cancelled host-calls=1 completion-polls=1 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=1 table-empty=true' <<<"$cancel"
grep -Fq 'mode=early-drop result=store-discarded host-calls=1 completion-polls=2 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=0 table-empty=not-applicable' <<<"$early_drop"
grep -Fq 'mode=repeat results=Ok,Ok host-calls=2 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 table-empty=true' <<<"$repeat"

printf 'D2 filesystem descriptor.metadata-hash Rust/Wasmtime runtime passed\n'
printf 'modes=ready,pending,error,repeat; cancel-and-early-drop=hand-authored-oracle\n'
