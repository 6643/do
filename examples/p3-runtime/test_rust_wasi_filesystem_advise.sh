#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-advise-probe.wit"
cancel_wit="$repo_root/examples/p3-runtime/wit/wasi-filesystem-advise-cancel-probe.wit"
core_wat="$repo_root/src/build/wasi_filesystem_advise_component_template.wat"
cancel_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-advise-cancel.runtime.core.wat"
invalid_core_wat="$repo_root/examples/p3-runtime/wasi-filesystem-advise-invalid.runtime.core.wat"
fixture="$repo_root/src/build/test/compile_ok/806_wasi_filesystem_advise_component.do"

for path in "$wit" "$cancel_wit" "$core_wat" "$cancel_core_wat" "$invalid_core_wat" "$fixture"; do
  [[ -f "$path" ]] || { printf 'missing descriptor.advise runtime input: %s\n' "$path" >&2; exit 1; }
done
rustfmt --edition 2024 --check "$runner_dir/src/bin/wasi_filesystem_advise.rs"
test -x "$toolchain_bin"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-d2-filesystem-advise-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

build_component() {
  local input_wit="$1" world="$2" wat="$3" name="$4"
  local core="$tmp_dir/$name.core.wasm" embedded="$tmp_dir/$name.embedded.wasm" component="$tmp_dir/$name.component.wasm"
  "$toolchain_bin" parse-core "$wat" -o "$core"
  "$toolchain_bin" validate-core "$core"
  "$toolchain_bin" embed-component "$input_wit" "$core" "$world" --features component-async -o "$embedded"
  "$toolchain_bin" new-component "$embedded" -o "$component"
  "$toolchain_bin" validate-component "$component" --features component-async
  printf '%s\n' "$component"
}

generated_wit="$tmp_dir/generated.wit"
generated_core_wat="$tmp_dir/generated.core.wat"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" --p3-async-component --p3-wit-output "$generated_wit" -o "$generated_core_wat" >/dev/null

component=$(build_component "$wit" advise-probe "$core_wat" advise)
cancel_component=$(build_component "$cancel_wit" advise-cancel-probe "$cancel_core_wat" advise-cancel)
invalid_component=$(build_component "$wit" advise-probe "$invalid_core_wat" advise-invalid)
generated_component=$(build_component "$generated_wit" advise-probe "$generated_core_wat" generated)

runner_env=(DO_D2_FILESYSTEM_ROOT="$tmp_dir/root" CC="$runner_dir/zig-cc.sh" CXX="$runner_dir/zig-cc.sh" CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh")
mkdir -p "$tmp_dir/root"
printf '12345678' > "$tmp_dir/root/file"

run_runner() {
  (cd "$runner_dir" && env "${runner_env[@]}" timeout 60s cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" --bin wasi-filesystem-advise -- "$1" "$2")
}

ready=$(run_runner "$component" ready)
pending=$(run_runner "$component" pending)
error=$(run_runner "$component" error)
all_advice=$(run_runner "$component" all-advice)
cancel=$(run_runner "$cancel_component" cancel)
invalid_advice=$(run_runner "$invalid_component" invalid-advice)
early_drop=$(run_runner "$component" early-drop)
repeat=$(run_runner "$component" repeat)
generated_ready=$(run_runner "$generated_component" ready)
generated_pending=$(run_runner "$generated_component" pending)
generated_error=$(run_runner "$generated_component" error)
generated_repeat=$(run_runner "$generated_component" repeat)

rg -Fq 'mode=ready result=Ok host-calls=1 observed-ranges=[(4096, 8192, 0)] mutations=0 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=8 table-empty=true' <<<"$ready"
rg -Fq 'mode=pending result=Ok host-calls=1 observed-ranges=[(4096, 8192, 0)] mutations=0 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=8 table-empty=true' <<<"$pending"
rg -Fq 'mode=error result=Err(no-entry) host-calls=1 observed-ranges=[(4096, 8192, 0)] mutations=0 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=8 table-empty=true' <<<"$error"
rg -Fq 'mode=all-advice host-calls=6 observed-ranges=[(4096, 8192, 0), (4096, 8192, 1), (4096, 8192, 2), (4096, 8192, 3), (4096, 8192, 4), (4096, 8192, 5)] mutations=0 completion-polls=6 external-wakes=0 completions=6 future-drops=6 pending-future-drops=0 descriptor-drops=6 file-size=8 table-empty=true' <<<"$all_advice"
rg -Fq 'mode=cancel result=cancelled host-calls=1 observed-ranges=[(4096, 8192, 0)] mutations=0 completion-polls=1 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=1 file-size=8 table-empty=true' <<<"$cancel"
rg -Fq 'mode=invalid-advice result=rejected raw-advice=6 host-calls=0 descriptor-drops=0 table-empty=not-applicable' <<<"$invalid_advice"
rg -Fq 'mode=early-drop result=store-discarded host-calls=1 observed-ranges=[(4096, 8192, 0)] mutations=0 completion-polls=2 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=0 file-size=8 table-empty=not-applicable' <<<"$early_drop"
rg -Fq 'mode=repeat results=Ok,Ok host-calls=2 observed-ranges=[(4096, 8192, 0), (4097, 8192, 1)] mutations=0 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 file-size=8 table-empty=true' <<<"$repeat"
rg -Fq 'mode=ready result=Ok host-calls=1 observed-ranges=[(4096, 8192, 0)] mutations=0 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=8 table-empty=true' <<<"$generated_ready"
rg -Fq 'mode=pending result=Ok host-calls=1 observed-ranges=[(4096, 8192, 0)] mutations=0 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=8 table-empty=true' <<<"$generated_pending"
rg -Fq 'mode=error result=Err(no-entry) host-calls=1 observed-ranges=[(4096, 8192, 0)] mutations=0 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 file-size=8 table-empty=true' <<<"$generated_error"
rg -Fq 'mode=repeat results=Ok,Ok host-calls=2 observed-ranges=[(4096, 8192, 0), (4097, 8192, 1)] mutations=0 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 file-size=8 table-empty=true' <<<"$generated_repeat"

printf 'D2 filesystem descriptor.advise Rust/Wasmtime runtime passed\n'
printf 'modes=ready,pending,error,all-advice,cancel,early-drop,repeat\n'
printf 'advice=normal:0,sequential:1,random:2,will-need:3,dont-need:4,no-reuse:5\n'
printf 'cancellation=advisory call has no rollback claim; pending state is cleaned exactly once\n'
