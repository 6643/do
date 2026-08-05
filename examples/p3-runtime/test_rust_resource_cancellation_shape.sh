#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
fixture="$repo_root/examples/p3-runtime/async-resource-result-cancel-component.do"
cargo_bin=${CARGO_BIN:-cargo}
rustc_bin=${RUSTC:-rustc}
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/resource-cancel-runtime.XXXXXX")
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

  sysroot_dir=$(mktemp -d "$tmp_root/resource-cancel-sysroot.XXXXXX")
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

core_path="$tmp_dir/generated.wat"
wit_path="$tmp_dir/generated.wit"
wasm_path="$tmp_dir/generated.wasm"
embedded_path="$tmp_dir/generated.embedded.wasm"
component_path="$tmp_dir/generated.component.wasm"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  --p3-async-component "$fixture" --p3-wit-output "$wit_path" -o "$core_path"
wasm-tools parse "$core_path" -o "$wasm_path"
wasm-tools component embed "$wit_path" "$wasm_path" \
  --world async-resource-cancel-probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

check_output() {
  local output=$1
  for marker in \
    "Rust P3 async resource cancellation probe passed" \
    "request consumed=1" \
    "pending future drops=1" \
    "response create=0" \
    "response drop=0" \
    "table-empty=true"; do
    case "$output" in
      *"$marker"*) ;;
      *)
        printf 'missing resource cancellation marker: %s\n' "$marker" >&2
        printf '%s\n' "$output" >&2
        exit 1
        ;;
    esac
  done
}

output=$("$cargo_bin" run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-resource-result-cancel-host-runner -- "$component_path")
check_output "$output"

wasm-tools parse "$repo_root/examples/p3-runtime/resource-result-cancel-probe.wat" \
  -o "$tmp_dir/probe.wasm"
wasm-tools component embed \
  "$repo_root/examples/p3-runtime/resource-result-cancel-probe.wit" \
  "$tmp_dir/probe.wasm" --world async-resource-cancel-probe \
  -o "$tmp_dir/probe.embedded.wasm"
wasm-tools component new "$tmp_dir/probe.embedded.wasm" \
  -o "$tmp_dir/probe.component.wasm"
wasm-tools validate --features cm-async,cm-more-async-builtins "$tmp_dir/probe.component.wasm"
probe_output=$("$cargo_bin" run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-resource-result-cancel-host-runner -- "$tmp_dir/probe.component.wasm")
check_output "$probe_output"

printf '%s\n' "$output"
printf 'pinned resource Result cancellation runtime probe passed\n'
