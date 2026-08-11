#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-set-size.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-set-size-cancel.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-set-size.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-set-size-cancel.core.wat"
fixture="$repo_root/src/build/test/compile_ok/552_wasi_filesystem_set_size_component.do"
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

for path in "$wit" "$cancel_wit" "$core_wat" "$cancel_core_wat" "$fixture"; do
  [[ -f "$path" ]] || {
    printf 'missing set-size runtime input: %s\n' "$path" >&2
    exit 1
  }
done

runner_source="$runner_dir/src/bin/wasi_filesystem_set_size.rs"
rustfmt --edition 2024 --check "$runner_source"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-set-size-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
root="$tmp_dir/root"
mkdir -p "$root"
printf '12345678' >"$root/file"

build_component() {
  local input_wit="$1"
  local world="$2"
  local wat="$3"
  local name="$4"
  local core="$tmp_dir/$name.core.wasm"
  local embedded="$tmp_dir/$name.embedded.wasm"
  local component="$tmp_dir/$name.component.wasm"
  "$wasm_tools" parse "$wat" -o "$core"
  "$wasm_tools" validate --features cm-async,cm-more-async-builtins "$core"
  "$wasm_tools" component embed "$input_wit" "$core" --world "$world" \
    --features cm-async,cm-more-async-builtins -o "$embedded"
  "$wasm_tools" component new --skip-validation "$embedded" -o "$component"
  "$wasm_tools" validate --features cm-async,cm-more-async-builtins "$component"
  printf '%s\n' "$component"
}

generated_wit="$tmp_dir/generated.wit"
generated_core_wat="$tmp_dir/generated.core.wat"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_core_wat" >/dev/null

component=$(build_component "$wit" set-size-probe "$core_wat" set-size)
cancel_component=$(build_component "$cancel_wit" set-size-cancel-probe "$cancel_core_wat" set-size-cancel)
generated_component=$(build_component "$generated_wit" set-size-probe "$generated_core_wat" generated)

runner_env=(
  DO_D2_FILESYSTEM_ROOT="$root"
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

run_runner() {
  local component_path="$1"
  local mode="$2"
  truncate -s 8 "$root/file"
  (cd "$runner_dir" && env "${runner_env[@]}" timeout 60s \
    cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
    --bin wasi-filesystem-set-size -- "$component_path" "$mode")
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

grep -Fq 'mode=ready result=Ok host-calls=1 observed-sizes=[4096] mutations=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=4096 table-empty=true' <<<"$ready"
grep -Fq 'mode=pending result=Ok host-calls=1 observed-sizes=[4096] mutations=1 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=4096 table-empty=true' <<<"$pending"
grep -Fq 'mode=error result=Err(no-entry) host-calls=1 observed-sizes=[4096] mutations=0 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=8 table-empty=true' <<<"$error"
grep -Fq 'mode=cancel result=cancelled host-calls=1 observed-sizes=[4096] mutations=1 completion-polls=1 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=1 file-size=4096 table-empty=true' <<<"$cancel"
grep -Fq 'mode=early-drop result=store-discarded host-calls=1 observed-sizes=[4096] mutations=1 completion-polls=2 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=0 file-size=4096 table-empty=not-applicable' <<<"$early_drop"
grep -Fq 'mode=repeat results=Ok,Ok host-calls=2 observed-sizes=[4096, 4097] mutations=2 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 file-size=4097 table-empty=true' <<<"$repeat"
grep -Fq 'mode=ready result=Ok host-calls=1 observed-sizes=[4096] mutations=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=4096 table-empty=true' <<<"$generated_ready"
grep -Fq 'mode=pending result=Ok host-calls=1 observed-sizes=[4096] mutations=1 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=4096 table-empty=true' <<<"$generated_pending"
grep -Fq 'mode=error result=Err(no-entry) host-calls=1 observed-sizes=[4096] mutations=0 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=8 table-empty=true' <<<"$generated_error"
grep -Fq 'mode=repeat results=Ok,Ok host-calls=2 observed-sizes=[4096, 4097] mutations=2 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 file-size=4097 table-empty=true' <<<"$generated_repeat"

printf 'D2 filesystem descriptor.set-size Rust/Wasmtime runtime passed\n'
printf 'modes=ready,pending,error,cancel,early-drop,repeat\n'
printf 'cancellation=issued file-size mutation is preserved; no rollback is attempted\n'
