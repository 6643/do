#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
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

core_path="$tmp_dir/async-resource-result.wat"
component_path="$tmp_dir/async-resource-result.component.wasm"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/async-resource-result-component.do" \
  --p3-async-component -o "$core_path"
wasm-tools parse "$core_path" -o "$tmp_dir/async-resource-result.wasm"
wasm-tools component embed "$repo_root/src/build/p3_async_resource_probe.wit" \
  "$tmp_dir/async-resource-result.wasm" --world async-resource-probe \
  -o "$tmp_dir/async-resource-result.embedded.wasm"
wasm-tools component new "$tmp_dir/async-resource-result.embedded.wasm" -o "$component_path"

output=$("$cargo_bin" run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-async-resource-result-host-runner -- "$component_path")

for marker in \
  "Rust P3 async resource Result pending adapter passed" \
  "request consumed=2" \
  "response create=2" \
  "response drop=2"; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing async resource Result marker: %s\n' "$marker" >&2
      printf '%s\n' "$output" >&2
      exit 1
      ;;
  esac
done

case "$output" in
  *"Rust P3 async resource Result pending adapter passed"*) ;;
  *)
    printf 'missing pending async resource Result marker\n%s\n' "$output" >&2
    exit 1
    ;;
esac

immediate_output=$(DO_P3_ASYNC_RESOURCE_IMMEDIATE=1 "$cargo_bin" run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-async-resource-result-host-runner -- "$component_path")

for marker in \
  "Rust P3 async resource Result immediate adapter passed" \
  "request consumed=2" \
  "response create=2" \
  "response drop=2"; do
  case "$immediate_output" in
    *"$marker"*) ;;
    *)
      printf 'missing immediate async resource Result marker: %s\n' "$marker" >&2
      printf '%s\n' "$immediate_output" >&2
      exit 1
      ;;
  esac
done

error_output=$(env DO_P3_ASYNC_RESOURCE_ERROR=1 timeout 10s "$cargo_bin" run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-async-resource-result-host-runner -- "$component_path")
for marker in \
  "Rust P3 async resource Result error adapter passed" \
  "request consumed=2" \
  "response create=0" \
  "response drop=0"; do
  case "$error_output" in
    *"$marker"*) ;;
    *)
      printf 'missing error async resource Result marker: %s\n' "$marker" >&2
      printf '%s\n' "$error_output" >&2
      exit 1
      ;;
  esac
done
