#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin=${DO_BIN:-"$repo_root/bin/do"}
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/g6-2-owned-record-producer-counters.XXXXXX")
failure_log="$repo_root/.superpowers/sdd/2026-09-14-g6-2-pilot-runtime-counter-gate/task-2-counter-gate-failure.log"
mkdir -p "$(dirname "$failure_log")"
cleanup() {
  if [[ -d "${tmp_dir:-}" ]]; then
    find "$tmp_dir" -depth -mindepth 1 -delete
    rmdir "$tmp_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

run_checked() {
  local label="$1"
  shift
  local stdout_file="$tmp_dir/$label.stdout"
  local stderr_file="$tmp_dir/$label.stderr"
  if "$@" >"$stdout_file" 2>"$stderr_file"; then
    cat "$stdout_file"
    return 0
  fi
  {
    printf 'step=%s\ncommand:' "$label"
    printf ' %q' "$@"
    printf '\nstdout:\n'
    cat "$stdout_file"
    printf '\nstderr:\n'
    cat "$stderr_file"
    printf '\n'
  } >>"$failure_log"
  printf 'G6.2 counter assembly step failed: %s; evidence=%s\n' "$label" "$failure_log" >&2
  cat "$stderr_file" >&2
  return 1
}

source="$repo_root/examples/p3-runtime/g6-2-owned-record-producer.do"
canonical_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-producer.wit"
counter_wit="$repo_root/examples/p3-runtime/wit/g6-2-owned-record-producer-counters.wit"
canonical_wat="$tmp_dir/canonical.wat"
generated_wit="$tmp_dir/generated.wit"
instrumented_wat="$tmp_dir/instrumented.wat"
instrumented_core="$tmp_dir/instrumented.core.wasm"
embedded="$tmp_dir/instrumented.embedded.wasm"
component="$tmp_dir/instrumented.component.wasm"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"

test -x "$do_bin"
test -x "$toolchain_bin"
test -f "$source"
test -f "$canonical_wit"
test -f "$counter_wit"
test -f "$runner_dir/Cargo.toml"

run_checked canonical-build env DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$source" \
  --p3-async-component --p3-wit-output "$generated_wit" -o "$canonical_wat"

cmp "$generated_wit" "$canonical_wit"
cmp "$canonical_wat" "$repo_root/src/build/owned_record_stream_producer_template.wat"
test "$(sha256sum "$canonical_wat" | awk '{print $1}')" = \
  095da7cd4c131a7318fc4bf5fd87b2d99e2672bff568edc577a553e228f856c5
test "$(sha256sum "$generated_wit" | awk '{print $1}')" = \
  6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace
test "$(sha256sum "$counter_wit" | awk '{print $1}')" = \
  a234fba271d5217b34ecedf665be9d2bf210dd449f37773d591a7cb306d2f9f5

run_checked instrument env ZIG_GLOBAL_CACHE_DIR="$repo_root/.tmp/zig-gcache" \
  ZIG_LOCAL_CACHE_DIR="$repo_root/.tmp/zig-cache" \
  zig run "$repo_root/src/build/pilot_runtime_counter_instrument.zig" -- \
  "$canonical_wat" "$instrumented_wat"

test "$(sha256sum "$instrumented_wat" | awk '{print $1}')" != \
  095da7cd4c131a7318fc4bf5fd87b2d99e2672bff568edc577a553e228f856c5
grep -Fq '[test-only-runtime-counters]' "$instrumented_wat"
grep -Fq '(export "runtime-counters"' "$instrumented_wat"
test "$(grep -Fo '(export "runtime-counters"' "$instrumented_wat" | wc -l | tr -d ' ')" = 1

run_checked parse-core "$toolchain_bin" parse-core "$instrumented_wat" -o "$instrumented_core"
run_checked embed-component "$toolchain_bin" embed-component "$counter_wit" "$instrumented_core" \
  owned-record-producer-counters --features component-async -o "$embedded"
run_checked new-component "$toolchain_bin" new-component "$embedded" -o "$component"
run_checked validate-component "$toolchain_bin" validate-component "$component" --features component-async

runner_bin=do-p3-g6-2-owned-record-producer-abi
if ! command -v cc >/dev/null 2>&1; then
  export CC="$runner_dir/zig-cc.sh"
  export CXX="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi
export ZIG_GLOBAL_CACHE_DIR="$repo_root/.tmp/zig-gcache"
export ZIG_LOCAL_CACHE_DIR="$repo_root/.tmp/zig-cache"

run_counter_mode() {
  local mode="$1"
  local output_file="$tmp_dir/counter-$mode.stdout"
  local error_file="$tmp_dir/counter-$mode.stderr"
  if ! cargo run --quiet --locked --manifest-path "$runner_dir/Cargo.toml" \
    --bin "$runner_bin" -- "$component" "$mode" --counter >"$output_file" 2>"$error_file"; then
    {
      printf 'step=counter-%s\ncommand: cargo run --quiet --locked --manifest-path %q --bin %q -- %q %q --counter\nstdout:\n' \
        "$mode" "$runner_dir/Cargo.toml" "$runner_bin" "$component" "$mode"
      cat "$output_file"
      printf '\nstderr:\n'
      cat "$error_file"
      printf '\n'
    } >>"$failure_log"
    printf 'G6.2 counter runtime step failed: %s; evidence=%s\n' "$mode" "$failure_log" >&2
    cat "$error_file" >&2
    return 1
  fi
  cat "$output_file"
  grep -Fq "mode=$mode" "$output_file"
  grep -Fq 'counter-source=component' "$output_file"
}

for mode in ready pending sink-error-before sink-error-after cancel-before-transfer cancel-after-transfer early-drop-before-transfer early-drop-after-transfer repeat invalid; do
  run_counter_mode "$mode"
done

printf 'G6.2 owned-record producer counter Component assembly/runtime gate passed\n'
printf 'canonical-wat-sha256=%s\n' "$(sha256sum "$canonical_wat" | awk '{print $1}')"
printf 'canonical-wit-sha256=%s\n' "$(sha256sum "$generated_wit" | awk '{print $1}')"
printf 'counter-wit-sha256=%s\n' "$(sha256sum "$counter_wit" | awk '{print $1}')"
printf 'instrumented-core-export=runtime-counters\n'
