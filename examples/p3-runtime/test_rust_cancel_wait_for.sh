#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
fixture="$repo_root/examples/p3-runtime/cancel-wait-for-component.wat"
wit="$repo_root/examples/p3-runtime/cancel-wait-for-component.wit"
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
  if ! command -v zig >/dev/null; then
    printf 'missing C linker: install cc or make zig available\n' >&2
    exit 1
  fi
  export CC="$runner_dir/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-cancel-wait-for.XXXXXX")
trap 'rm -rf -- "$tmpdir"; if [ -n "${sysroot_dir:-}" ]; then rm -rf -- "$sysroot_dir"; fi' EXIT
embedded="$tmpdir/cancel-wait-for.embedded.wasm"
component=${DO_P3_COMPONENT:-}
if [ -z "$component" ]; then
  component="$tmpdir/cancel-wait-for.component.wasm"
  wasm-tools component embed "$wit" "$fixture" --world probe -o "$embedded"
  wasm-tools component new "$embedded" -o "$component"
  wasm-tools validate "$component"
fi

output=$("$cargo_bin" run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-cancel-wait-for-host-runner -- "$component")

for marker in \
  "Rust P3 cancel pending adapter passed" \
  "cancel before completion observed" \
  "terminal subtask is not completed twice"; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing cancellation marker: %s\n' "$marker" >&2
      printf '%s\n' "$output" >&2
      exit 1
      ;;
  esac
done

immediate_output=$(DO_P3_CANCEL_IMMEDIATE=1 "$cargo_bin" run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-cancel-wait-for-host-runner -- "$component")
for marker in \
  "Rust P3 cancel immediate adapter passed" \
  "cancel before completion observed" \
  "terminal subtask is not completed twice"; do
  case "$immediate_output" in
    *"$marker"*) ;;
    *)
      printf 'missing immediate cancellation marker: %s\n' "$marker" >&2
      printf '%s\n' "$immediate_output" >&2
      exit 1
      ;;
  esac
done
