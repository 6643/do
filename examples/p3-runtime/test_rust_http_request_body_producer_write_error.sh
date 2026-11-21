#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-body-producer-write-error-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/producer.wat"
core_wasm="$tmp_dir/producer.wasm"
embedded="$tmp_dir/producer.embedded.wasm"
component="$tmp_dir/producer.component.wasm"
wit_dir="$tmp_dir/wit-package"

test -x "$toolchain_bin"
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/http-request-body-producer-write-error.do" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"
"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
cat >>"$wit_dir/worlds.wit" <<'WIT'

interface probe {
  variant producer-error { http-failure, stream-closed, stream-write-failed }
  run: async func() -> result<_, producer-error>;
}

world http-request-body-producer-write-error-probe {
  import types;
  import client;
  import wasi:cli/stdout@0.3.0-rc-2025-09-16;
  export probe;
}
WIT
"$toolchain_bin" embed-component "$wit_dir" "$core_wasm" \
  http-request-body-producer-write-error-probe --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

runner_env=(
  CC="$runner_dir/zig-cc.sh"
  CXX="$runner_dir/zig-cc.sh"
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_dir/zig-cc.sh"
)
output=$(cd "$runner_dir" && env "${runner_env[@]}" \
  timeout 90s cargo run --quiet \
    --bin do-p3-http-request-body-producer-write-error-host-runner -- "$component")

for marker in \
  'Rust P3 HTTP request body producer write-error passed' \
  'result=Err(StreamClosed)' \
  'body-payload=[65]' \
  'send-cancellations=1' \
  'body-stream-drops=1' \
  'transmission-future-drops=1' \
  'trailers-future-drops=1' \
  'responses=0' \
  'table-empty=true'; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2
      exit 1
      ;;
  esac
done

printf '%s\n' "$output"
printf 'WASI HTTP request body producer write-error runtime passed\n'
