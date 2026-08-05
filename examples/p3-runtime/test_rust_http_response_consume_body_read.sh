#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-response-body-read-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/response-body-read.wat"
core_wasm="$tmp_dir/response-body-read.wasm"
embedded="$tmp_dir/response-body-read.embedded.wasm"
component="$tmp_dir/response-body-read.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/http-response-consume-body-read.do" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

cat >>"$wit_dir/worlds.wit" <<'WIT'

interface probe {
  use types.{response};
  run: async func(response: response);
}

world http-response-body-probe {
  import types;
  export probe;
}
WIT

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world http-response-body-probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-http-response-consume-body-host-runner -- "$component" 1)
for marker in \
  'Rust P3 HTTP response consume-body adapter passed' \
  'response-consumed=1' \
  'body-bytes=1' \
  'stream-drops=1' \
  'future-drops=1' \
  'table-empty=true'; do
  case "$output" in
    *"$marker"*) ;;
    *) printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2; exit 1 ;;
  esac
done

printf 'WASI HTTP response consume-body one-read runtime passed\n'
