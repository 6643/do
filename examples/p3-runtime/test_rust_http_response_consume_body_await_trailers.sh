#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-response-body-await-trailers-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/response-body-await-trailers.wat"
core_wasm="$tmp_dir/response-body-await-trailers.wasm"
embedded="$tmp_dir/response-body-await-trailers.embedded.wasm"
component="$tmp_dir/response-body-await-trailers.component.wasm"

test -x "$toolchain_bin"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/http-response-consume-body-await-trailers.do" \
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

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_dir" "$core_wasm" http-response-body-probe \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

if ! command -v cc >/dev/null; then
    export CC="$runner_dir/zig-cc.sh"
    export CXX="$runner_dir/zig-cc.sh"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
fi

check_output() {
  local output=$1
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
}

output=$(timeout 10s cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-http-response-consume-body-host-runner -- "$component" 1 1 0)
check_output "$output"

output=$(cargo run --quiet --manifest-path "$runner_dir/Cargo.toml" \
  --bin do-p3-http-response-consume-body-host-runner -- "$component" 1 1 1)
check_output "$output"

printf 'WASI HTTP response trailers await runtime passed\n'
