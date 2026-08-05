#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
component_path=${DO_P3_COMPONENT:?DO_P3_COMPONENT is required}
cargo_bin=${CARGO_BIN:-cargo}
rustc_bin=${RUSTC:-rustc}

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
  export CC="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

output=$("$cargo_bin" run --quiet --manifest-path "$runner_dir/Cargo.toml" --bin cli_result_probe -- "$component_path")
case "$output" in
  *"Rust P3 CLI Result pending adapter passed parallel-calls=2"*) ;;
  *) printf 'missing parallel CLI Result success marker\n%s\n' "$output" >&2; exit 1 ;;
esac

immediate_output=$(DO_P3_CLI_RESULT_IMMEDIATE=1 "$cargo_bin" run --quiet --manifest-path "$runner_dir/Cargo.toml" --bin cli_result_probe -- "$component_path")
case "$immediate_output" in
  *"Rust P3 CLI Result immediate adapter passed parallel-calls=2"*) ;;
  *) printf 'missing immediate parallel CLI Result success marker\n%s\n' "$immediate_output" >&2; exit 1 ;;
esac
