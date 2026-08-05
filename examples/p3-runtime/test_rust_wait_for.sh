#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
manifest_path="$runner_dir/Cargo.toml"
cargo_bin=${CARGO_BIN:-cargo}
rustc_bin=${RUSTC:-rustc}
expected_duration=${DO_P3_CLOCK_EXPECTED_DURATION:-27815}

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
  trap 'rm -rf -- "$sysroot_dir"' EXIT
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

component_path=${DO_P3_COMPONENT:-"$repo_root/examples/p3-runtime/async-wait-for-component.wat"}

output=$("$cargo_bin" run --quiet --manifest-path "$manifest_path" --bin do-p3-wait-for-host-runner -- "$component_path")

case "$output" in
  *"Rust P3 clocks pending adapter passed"*) ;;
  *)
    printf 'missing Rust P3 clocks success marker\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"clock argument=$expected_duration"*) ;;
  *)
    printf 'missing clock argument marker\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"clock pending-polls=1"*) ;;
  *)
    printf 'missing clock pending-polls marker\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"clock external-wakes=1"*) ;;
  *)
    printf 'missing clock external-wakes marker\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"clock completions=1"*) ;;
  *)
    printf 'missing clock completions marker\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
    ;;
esac

immediate_output=$(DO_P3_CLOCK_IMMEDIATE=1 "$cargo_bin" run --quiet --manifest-path "$manifest_path" --bin do-p3-wait-for-host-runner -- "$component_path")

for marker in \
  "Rust P3 clocks immediate adapter passed" \
  "clock argument=$expected_duration" \
  "clock pending-polls=0" \
  "clock external-wakes=0" \
  "clock completions=0"; do
  case "$immediate_output" in
    *"$marker"*) ;;
    *)
      printf 'missing immediate clocks marker: %s\n' "$marker" >&2
      printf '%s\n' "$immediate_output" >&2
      exit 1
      ;;
  esac
done
