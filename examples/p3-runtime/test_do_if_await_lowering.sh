#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-if-await.XXXXXX")
core_path="$tmp_dir/if-await.wat"
wit_path="$tmp_dir/if-await.wit"
embedded_path="$tmp_dir/if-await.embedded.wasm"
component_path="$tmp_dir/if-await.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$repo_root/examples/p3-runtime/if-await-component.do" \
  --p3-async-component --p3-wit-output "$wit_path" -o "$core_path"

grep -Fq 'i64.const 27815' "$core_path"
grep -Fq 'i64.eq' "$core_path"
grep -Fq 'call $first-host-call' "$core_path"
grep -Fq 'call $second-host-call' "$core_path"
grep -Fq 'wait-for: async func(how-long: u64)' "$wit_path"
grep -Fq 'wait-until: async func(when: u64)' "$wit_path"

wasm-tools component embed "$wit_path" "$core_path" --world probe -o "$embedded_path"
wasm-tools component new "$embedded_path" -o "$component_path"
wasm-tools validate "$component_path"

if ! command -v cc >/dev/null; then
  if ! command -v zig >/dev/null; then
    printf 'missing C linker: install cc or make zig available\n' >&2
    exit 1
  fi
  export CC="$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh"
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$repo_root/examples/p3-runtime/rust-host-runner/zig-cc.sh"
fi

output=$(cargo run --quiet --manifest-path "$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml" --bin do-p3-two-await-host-runner -- "$component_path" --if-branch)
for marker in \
  'Rust P3 if-branch adapter passed' \
  'clock parallel-calls=2' \
  'clock pending-polls=2' \
  'clock external-wakes=2' \
  'clock completions=2'; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing if-await runner marker: %s\n' "$marker" >&2
      printf '%s\n' "$output" >&2
      exit 1
      ;;
  esac
done
