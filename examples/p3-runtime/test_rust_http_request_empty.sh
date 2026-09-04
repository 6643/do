#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-empty-runtime.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/request.wat"
core_wasm="$tmp_dir/request.wasm"
embedded="$tmp_dir/request.embedded.wasm"
component="$tmp_dir/request.component.wasm"

test -x "$toolchain_bin"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/examples/p3-runtime/http-request-empty.do" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

cat >>"$wit_dir/worlds.wit" <<'WIT'

interface probe {
  run: async func();
}

world http-request-probe {
  import types;
  export probe;
}
WIT

"$toolchain_bin" parse-core "$core_wat" -o "$core_wasm"
"$toolchain_bin" embed-component "$wit_dir" "$core_wasm" http-request-probe \
  --features component-async -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component" --features component-async

output=$(cd "$runner_dir" && \
  CC="$PWD/zig-cc.sh" \
  CXX="$PWD/zig-cc.sh" \
  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/zig-cc.sh" \
  timeout 30s cargo run --quiet --bin do-p3-http-request-new-host-runner -- "$component")
for marker in \
  'Rust P3 HTTP request constructor adapter passed' \
  'constructors=2' \
  'fields-drops=2' \
  'requests=2' \
  'request-drops=2' \
  'transmission-future-drops=2' \
  'trailers-future-drops=2' \
  'table-empty=true'; do
  case "$output" in
    *"$marker"*) ;;
    *)
      printf 'missing marker: %s\n%s\n' "$marker" "$output" >&2
      exit 1
      ;;
  esac
done

printf 'WASI HTTP empty request runtime passed\n'
