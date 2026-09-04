#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
runner_source="$runner_dir/src/bin/wasi_filesystem_get_flags.rs"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-get-flags.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-get-flags-cancel.wit"
core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-get-flags.core.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-get-flags-cancel.core.wat"

test -f "$runner_source"
test -f "$wit"
test -f "$cancel_wit"
test -f "$core_wat"
test -f "$cancel_core_wat"
test -x "$toolchain_bin"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-get-flags-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
root="$tmp_dir/root"
mkdir -p "$root/dir"
printf 'd2-get-flags\n' >"$root/file"

core_wasm="$tmp_dir/get-flags.core.wasm"
embedded="$tmp_dir/get-flags.embedded.wasm"
component="$tmp_dir/get-flags.component.wasm"
cancel_core_wasm="$tmp_dir/get-flags-cancel.core.wasm"
cancel_embedded="$tmp_dir/get-flags-cancel.embedded.wasm"
cancel_component="$tmp_dir/get-flags-cancel.component.wasm"
generated_wit="$tmp_dir/generated.wit"
generated_core_wat="$tmp_dir/generated.core.wat"
generated_core_wasm="$tmp_dir/generated.core.wasm"
generated_embedded="$tmp_dir/generated.embedded.wasm"
generated_component="$tmp_dir/generated.component.wasm"

"$repo_root/bin/do" build "$repo_root/src/build/test/compile_ok/471_wasi_filesystem_get_flags_component.do" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_core_wat"
"$toolchain_bin" parse-core "$generated_core_wat" -o "$generated_core_wasm"
"$toolchain_bin" embed-component "$generated_wit" "$generated_core_wasm" get-flags-probe \
  --features component-async -o "$generated_embedded"
"$toolchain_bin" new-component "$generated_embedded" -o "$generated_component"
"$toolchain_bin" validate-component "$generated_component" --features component-async
grep -Fq 'get-flags: async func() -> result<descriptor-flags, error-code>;' "$generated_wit"
grep -Fq 'run: async func(directory: own<descriptor>) -> result<descriptor-flags, error-code>;' "$generated_wit"
grep -Fq '"[async-lower][method]descriptor.get-flags"' "$generated_core_wat"
grep -Fq '"[resource-drop]descriptor"' "$generated_core_wat"

rustfmt --edition 2024 --check "$runner_source"

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit" "$core_wasm" get-flags-probe \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async
"$toolchain_bin" parse-core "$cancel_core_wat" -o "$cancel_core_wasm"
"$toolchain_bin" embed-component "$cancel_wit" "$cancel_core_wasm" get-flags-cancel-probe \
  --features component-async -o "$cancel_embedded"
"$toolchain_bin" new-component "$cancel_embedded" -o "$cancel_component"
"$toolchain_bin" validate-component "$cancel_component" --features component-async

runner_env=(
  DO_D2_FILESYSTEM_ROOT="$root"
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)

run_runner() {
  local component_path=$1
  local mode=$2
  env "${runner_env[@]}" timeout 60s cargo run --quiet \
    --manifest-path "$runner_dir/Cargo.toml" \
    --bin do-p3-wasi-filesystem-get-flags-host-runner -- "$component_path" "$mode"
}

ready=$(run_runner "$component" ready)
pending=$(run_runner "$component" pending)
error=$(run_runner "$component" error)
cancel=$(run_runner "$cancel_component" cancel)
generated_ready=$(run_runner "$generated_component" ready)
generated_pending=$(run_runner "$generated_component" pending)
generated_error=$(run_runner "$generated_component" error)

grep -Fq 'mode=ready result=Ok(read|write) host-calls=1 completion-polls=1 external-wakes=0 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$ready"
grep -Fq 'mode=pending result=Ok(read|write) host-calls=1 completion-polls=2 external-wakes=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$pending"
grep -Fq 'mode=error result=Err(no-entry) host-calls=1 completion-polls=1 external-wakes=0 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$error"
grep -Fq 'mode=cancel result=cancelled host-calls=1 completion-polls=1 external-wakes=0 future-drops=1 pending-future-drops=1 descriptor-drops=1 table-empty=true' <<<"$cancel"
grep -Fq 'mode=ready result=Ok(read|write) host-calls=1 completion-polls=1 external-wakes=0 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$generated_ready"
grep -Fq 'mode=pending result=Ok(read|write) host-calls=1 completion-polls=2 external-wakes=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$generated_pending"
grep -Fq 'mode=error result=Err(no-entry) host-calls=1 completion-polls=1 external-wakes=0 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true' <<<"$generated_error"

printf '%s\n' "$ready" "$pending" "$error" "$cancel" "$generated_ready" "$generated_pending" "$generated_error"
printf 'D2 filesystem descriptor.get-flags Rust/Wasmtime runtime passed\n'
