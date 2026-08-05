#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-two-await.XXXXXX")
core_path="$tmp_dir/two-await.wat"
wit_path="$tmp_dir/two-await.wit"
embedded_path="$tmp_dir/two-await.embedded.wasm"
component_path="$tmp_dir/two-await.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$repo_root/examples/p3-runtime/two-await-component.do" \
  --p3-async-component --p3-wit-output "$wit_path" -o "$core_path"

grep -Fq '[async-lower]wait-for' "$core_path"
grep -Fq '[async-lower]wait-until' "$core_path"
grep -Fq '(type $async-frame (struct' "$core_path"
grep -Fq '(table $async-frames 0 (ref null $async-frame))' "$core_path"
grep -Fq 'table.get $async-frames' "$core_path"
if grep -Fq 'global $frame-next' "$core_path"; then
  printf 'P3 two-await lowering still uses the linear-memory frame allocator\n' >&2
  exit 1
fi
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

output=$(cargo run --quiet --manifest-path "$repo_root/examples/p3-runtime/rust-host-runner/Cargo.toml" --bin do-p3-two-await-host-runner -- "$component_path")

for marker in \
  'Rust P3 two-await adapter passed' \
  'clock parallel-calls=2' \
  'clock pending-polls=4' \
  'clock external-wakes=4' \
  'clock completions=4'; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing two-await runner marker: %s\n' "$marker" >&2
      printf '%s\n' "$output" >&2
      exit 1
      ;;
  esac
done

literal_core_path="$tmp_dir/literal-two-await.wat"
literal_wit_path="$tmp_dir/literal-two-await.wit"
literal_embedded_path="$tmp_dir/literal-two-await.embedded.wasm"
literal_component_path="$tmp_dir/literal-two-await.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$repo_root/examples/p3-runtime/literal-two-await-component.do" \
  --p3-async-component --p3-wit-output "$literal_wit_path" -o "$literal_core_path"

if [ "$(grep -Fc 'i64.const 41' "$literal_core_path")" -lt 2 ]; then
  printf 'literal two-await lowering did not replay the u64 literal at both host calls\n' >&2
  exit 1
fi
if [ "$(grep -Fc 'i64.add' "$literal_core_path")" -lt 2 ]; then
  printf 'literal two-await lowering did not replay the u64 addition at both host calls\n' >&2
  exit 1
fi

wasm-tools component embed "$literal_wit_path" "$literal_core_path" --world probe -o "$literal_embedded_path"
wasm-tools component new "$literal_embedded_path" -o "$literal_component_path"
wasm-tools validate "$literal_component_path"
