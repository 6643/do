#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/../.." && pwd -P)
reference_dir="$repo_root/.deps/wit-bindgen"
reference_commit="1ae00530221542369d0e47ee4a1f4232f09d978d"
reference_tag="v0.60.0"
wit_file="$script_dir/async-world.wit"
reference_bin="$reference_dir/target/debug/wit-bindgen"

die() {
  printf 'wit-bindgen differential probe: %s\n' "$*" >&2
  exit 1
}

test -d "$reference_dir/.git" || die "missing .deps/wit-bindgen checkout"
actual_commit=$(git -C "$reference_dir" rev-parse HEAD)
test "$actual_commit" = "$reference_commit" ||
  die "reference commit $actual_commit does not match $reference_commit"
tag_commit=$(git -C "$reference_dir" rev-parse "$reference_tag^{commit}")
test "$tag_commit" = "$reference_commit" ||
  die "reference tag $reference_tag resolves to $tag_commit, expected $reference_commit"
test -f "$wit_file" || die "missing $wit_file"

build_reference() {
  if test -x "$reference_bin"; then
    return
  fi

  command -v cargo >/dev/null 2>&1 || die "cargo is required to build the reference CLI"

  if command -v cc >/dev/null 2>&1; then
    cargo build --locked --manifest-path "$reference_dir/Cargo.toml"
    return
  fi

  command -v zig >/dev/null 2>&1 || die "cc or zig is required to build the reference CLI"
  linker_dir=$(mktemp -d)
  linker="$linker_dir/zig-cc"
  printf '#!/bin/sh\nexec %q cc "$@"\n' "$(command -v zig)" >"$linker"
  chmod +x "$linker"
  CC="$linker" CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$linker" \
    cargo build --locked --manifest-path "$reference_dir/Cargo.toml"
  rm -rf -- "$linker_dir"
}

build_reference
test -x "$reference_bin" || die "reference CLI was not built"

tmp_dir=$(mktemp -d "$repo_root/.tmp/wit-bindgen-do-diff.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/go" "$tmp_dir/rust"

"$reference_bin" go --format=false --out-dir "$tmp_dir/go" --world probe "$wit_file"
"$reference_bin" rust --out-dir "$tmp_dir/rust" --world probe "$wit_file"

go_output="$tmp_dir/go/do_bindgen_probe_api/wit_bindings.go"
rust_output="$tmp_dir/rust/probe.rs"
test -f "$go_output" || die "Go generator did not emit $go_output"
test -f "$rust_output" || die "Rust generator did not emit $rust_output"

check_needles() {
  local source_file=$1
  local expected_file=$2
  while IFS= read -r needle; do
    test -n "$needle" || continue
    rg -F --quiet -- "$needle" "$source_file" ||
      die "missing '$needle' in $source_file"
  done <"$expected_file"
}

check_needles "$go_output" "$script_dir/expected/go_api.txt"
check_needles "$rust_output" "$script_dir/expected/rust_api.txt"

for needle in \
  'go: future readable/writable/drop operations are generated for completion' \
  'go: stream readable/writable/drop operations are generated for events' \
  'go: async import send uses [async-lower] and SubtaskWait' \
  'rust: async import send uses an async fn and [async-lower]' \
  'rust: resources expose [resource-drop] operations for request and response' \
  'cancellation: runtime terminal protocol, not a WIT member'; do
  rg -F --quiet -- "$needle" "$script_dir/expected/abi_matrix.txt" ||
    die "missing differential matrix row '$needle'"
done

printf 'wit-bindgen differential probe: PASS\n'
printf 'reference=%s\n' "$actual_commit"
printf 'go=%s\n' "$go_output"
printf 'rust=%s\n' "$rust_output"
