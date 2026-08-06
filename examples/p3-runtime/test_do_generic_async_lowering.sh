#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$repo_root/examples/p3-runtime/generic-async-single-future.do"
wit="$repo_root/examples/p3-runtime/generic-async-single-future.wit"
runner_manifest="$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-generic-async.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/generic-async.wat"
core_wasm="$tmp_dir/generic-async.core.wasm"
embedded="$tmp_dir/generic-async.embedded.wasm"
component="$tmp_dir/generic-async.component.wasm"

"$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-output "$tmp_dir/generated.wit" -o "$core_wat"
cmp "$wit" "$tmp_dir/generated.wit"

for marker in \
  'do:generic-async-probe/host@0.1.0' \
  '[async-lift]run' \
  '[callback][async-lift]run' \
  '[task-return]run' \
  '[subtask-cancel]' \
  '[subtask-drop]' \
  'generic-async contract'; do
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
    --bin do-p3-generic-async-single-future-host-runner -- "$component"
}

pending_output=$(run_runner)
case "$pending_output" in
  *'generic async pending path passed'*'generic async completion=1'*'generic async terminal cleanup=1'*'generic async cancel path has no second completion'*) ;;
  *)
    printf 'generic async pending path failed:\n%s\n' "$pending_output" >&2
    exit 1
    ;;
esac

immediate_output=$(DO_GENERIC_ASYNC_IMMEDIATE=1 run_runner)
case "$immediate_output" in
  *'generic async immediate-ready path passed'*'generic async completion=1'*'generic async terminal cleanup=1'*'generic async cancel path has no second completion'*) ;;
  *)
    printf 'generic async immediate path failed:\n%s\n' "$immediate_output" >&2
    exit 1
    ;;
esac

printf 'generic async Component lowering passed\n'
