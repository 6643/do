#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$repo_root/examples/p3-runtime/generic-async-runtime.do"
wit="$repo_root/examples/p3-runtime/generic-async-runtime.wit"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-generic-async-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/generic-async-runtime.wat"
core_wasm="$tmp_dir/generic-async-runtime.core.wasm"
embedded="$tmp_dir/generic-async-runtime.embedded.wasm"
component="$tmp_dir/generic-async-runtime.component.wasm"

"$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-output "$tmp_dir/generated.wit" -o "$core_wat"
cmp "$wit" "$tmp_dir/generated.wit"

for marker in \
  'do:generic-async-runtime-probe/host@0.1.0' \
  '[async-lower]work' \
  'call $host-work' \
  'call $subtask-cancel' \
  'call $subtask-drop' \
  'call $waitable-set-drop' \
  'call $task-return'; do
  grep -Fq "$marker" "$core_wat"
done

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" --world probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

cargo_bin=${CARGO_BIN:-cargo}
if ! command -v cc >/dev/null && command -v zig >/dev/null; then
  export CC="$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$CC"
fi

run_runner() {
  "$cargo_bin" run --quiet --locked --manifest-path "$runner_manifest" \
    --bin do-p3-generic-async-runtime-host-runner -- "$component"
}

pending_output=$(DO_GENERIC_ASYNC_RUNTIME_MODE=pending run_runner)
grep -Fq 'pending external-wakes=2 completions=2 drops=1' <<<"$pending_output"

immediate_output=$(DO_GENERIC_ASYNC_RUNTIME_MODE=immediate run_runner)
grep -Fq 'immediate external-wakes=0 completions=3 drops=0' <<<"$immediate_output"

cancel_output=$(DO_GENERIC_ASYNC_RUNTIME_MODE=cancel run_runner)
grep -Fq 'cancel cancel-before-completion=1 completions=2' <<<"$cancel_output"

printf 'generic async runtime pending/ready/cancel passed\n'
