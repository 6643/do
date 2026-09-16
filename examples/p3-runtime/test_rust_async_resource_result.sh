#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
cargo_bin=${CARGO_BIN:-cargo}
rustc_bin=${RUSTC:-rustc}
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-async-resource-result.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

target_libdir=$("$rustc_bin" --print target-libdir)
if ! compgen -G "$target_libdir/libstd*.rlib" >/dev/null; then
  rust_root=${DO_P3_RUST_ROOT:-/home/_/Public/rust}
  cargo_bin="$rust_root/cargo/bin/cargo"
  rustc_bin="$rust_root/rustc/bin/rustc"
  std_libdir="$rust_root/rust-std-x86_64-unknown-linux-gnu/lib/rustlib"
  if [ ! -x "$cargo_bin" ] || [ ! -x "$rustc_bin" ] || [ ! -d "$std_libdir" ]; then
    printf 'missing a Rust sysroot with x86_64-unknown-linux-gnu std\n' >&2
    exit 1
  fi

  sysroot_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-rust-sysroot.XXXXXX")
  trap 'rm -rf -- "$tmp_dir" "$sysroot_dir"' EXIT
  mkdir -p "$sysroot_dir/lib"
  ln -s "$std_libdir" "$sysroot_dir/lib/rustlib"
  export RUSTC="$rustc_bin"
  export RUSTC_BOOTSTRAP=1
  export RUSTFLAGS="${RUSTFLAGS:-} -Zunstable-options --sysroot=$sysroot_dir"
fi

if ! command -v cc >/dev/null; then
  if ! command -v zig >/dev/null; then
    printf 'missing C linker: install cc or make zig available\n' >&2
    exit 1
  fi
  export CC="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

test -x "$toolchain_bin"

core_path="$tmp_dir/async-resource-result.wat"
component_path="$tmp_dir/async-resource-result.component.wasm"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/async-resource-result-component.do" \
  --p3-async-component -o "$core_path"
"$toolchain_bin" parse-core "$core_path" -o "$tmp_dir/async-resource-result.wasm"
"$toolchain_bin" embed-component "$repo_root/src/build/p3_async_resource_probe.wit" \
  "$tmp_dir/async-resource-result.wasm" async-resource-probe \
  --features component-async -o "$tmp_dir/async-resource-result.embedded.wasm"
"$toolchain_bin" new-component "$tmp_dir/async-resource-result.embedded.wasm" -o "$component_path"

linear_component_path="${DO_P3_ASYNC_RESOURCE_LINEAR_COMPONENT:-}"
if [[ -n "$linear_component_path" && ! -f "$linear_component_path" ]]; then
  printf 'missing linear async resource Result component: %s\n' "$linear_component_path" >&2
  exit 1
fi

run_component_mode() {
  local component=$1
  local mode=$2
  case "$mode" in
    pending)
      env -u DO_P3_ASYNC_RESOURCE_IMMEDIATE -u DO_P3_ASYNC_RESOURCE_ERROR \
        -u DO_P3_ASYNC_RESOURCE_REPEAT "$cargo_bin" run --quiet \
        --manifest-path "$runner_dir/Cargo.toml" \
        --bin do-p3-async-resource-result-host-runner -- "$component"
      ;;
    immediate)
      env -u DO_P3_ASYNC_RESOURCE_ERROR -u DO_P3_ASYNC_RESOURCE_REPEAT \
        DO_P3_ASYNC_RESOURCE_IMMEDIATE=1 "$cargo_bin" run --quiet \
        --manifest-path "$runner_dir/Cargo.toml" \
        --bin do-p3-async-resource-result-host-runner -- "$component"
      ;;
    error)
      env -u DO_P3_ASYNC_RESOURCE_IMMEDIATE -u DO_P3_ASYNC_RESOURCE_REPEAT \
        DO_P3_ASYNC_RESOURCE_ERROR=1 timeout 10s "$cargo_bin" run --quiet \
        --manifest-path "$runner_dir/Cargo.toml" \
        --bin do-p3-async-resource-result-host-runner -- "$component"
      ;;
    repeat)
      env -u DO_P3_ASYNC_RESOURCE_IMMEDIATE -u DO_P3_ASYNC_RESOURCE_ERROR \
        DO_P3_ASYNC_RESOURCE_REPEAT=1 "$cargo_bin" run --quiet \
        --manifest-path "$runner_dir/Cargo.toml" \
        --bin do-p3-async-resource-result-host-runner -- "$component"
      ;;
    *)
      printf 'unknown async resource Result mode: %s\n' "$mode" >&2
      exit 1
      ;;
  esac
}

assert_case_output() {
  local case_name=$1
  local output=$2
  local marker=$3
  local request_count=$4
  local response_count=$5
  for marker_text in \
    "$marker" \
    "request consumed=$request_count" \
    "response create=$response_count" \
    "response drop=$response_count" \
    "table-empty=true"; do
    case "$output" in
      *"$marker_text"*) ;;
      *)
        printf 'missing %s async resource Result marker: %s\n' "$case_name" "$marker_text" >&2
        printf '%s\n' "$output" >&2
        exit 1
        ;;
    esac
  done
}

extract_resource_observation() {
  local output=$1
  printf '%s\n' "$output" | grep -E '^(request consumed|response create|response drop|table-empty)='
}

resource_record() {
  local case_name=$1
  local backend=$2
  local output=$3
  local request_count=$4
  local response_count=$5
  local request create drop table
  request=$(printf '%s\n' "$output" | grep -Fx "request consumed=$request_count")
  create=$(printf '%s\n' "$output" | grep -Fx "response create=$response_count")
  drop=$(printf '%s\n' "$output" | grep -Fx "response drop=$response_count")
  table=$(printf '%s\n' "$output" | grep -Fx 'table-empty=true')
  printf 'resource lifecycle case=%s backend=%s %s %s %s %s\n' \
    "$case_name" "$backend" "$request" "$create" "$drop" "$table"
}

run_case() {
  local case_name=$1
  local mode=$2
  local marker=$3
  local request_count=$4
  local response_count=$5
  local output linear_output
  output=$(run_component_mode "$component_path" "$mode")
  assert_case_output "$case_name" "$output" "$marker" "$request_count" "$response_count"
  if [[ -n "$linear_component_path" ]]; then
    linear_output=$(run_component_mode "$linear_component_path" "$mode")
    assert_case_output "$case_name" "$linear_output" "$marker" "$request_count" "$response_count"
    if [[ "$(extract_resource_observation "$output")" != "$(extract_resource_observation "$linear_output")" ]]; then
      printf 'GC/linear resource lifecycle mismatch: case=%s\n' "$case_name" >&2
      diff -u \
        <(extract_resource_observation "$output") \
        <(extract_resource_observation "$linear_output") >&2 || true
      exit 1
    fi
    resource_record "$case_name" gc "$output" "$request_count" "$response_count"
    resource_record "$case_name" linear "$linear_output" "$request_count" "$response_count"
    printf 'resource lifecycle equivalence case=%s passed\n' "$case_name"
  else
    resource_record "$case_name" gc "$output" "$request_count" "$response_count"
  fi
}

run_case pending pending "Rust P3 async resource Result pending adapter passed" 2 2
run_case ready immediate "Rust P3 async resource Result immediate adapter passed" 2 2
run_case error error "Rust P3 async resource Result error adapter passed" 2 0
run_case repeat repeat "Rust P3 async resource Result repeat adapter passed" 4 4
