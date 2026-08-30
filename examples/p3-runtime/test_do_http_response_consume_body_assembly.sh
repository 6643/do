#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="$repo_root/bin/do-toolchain"
export DO_TOOLCHAIN_LOCK="$repo_root/toolchain/toolchain.lock.json"
do_bin="$repo_root/bin/do"
fixture="$repo_root/examples/p3-runtime/http-response-consume-body.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-response-body.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/response-body.wat"
core_wasm="$tmp_dir/response-body.wasm"
embedded="$tmp_dir/response-body.embedded.wasm"
component="$tmp_dir/response-body.component.wasm"
component_wat="$tmp_dir/response-body.component.wat"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
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
"$toolchain_bin" embed-component "$wit_dir" "$core_wasm" \
  http-response-body-probe -o "$embedded"
"$toolchain_bin" new-component "$embedded" -o "$component"
"$toolchain_bin" validate-component "$component"
"$toolchain_bin" print-component "$component" >"$component_wat"
grep -Fq 'call $consume-body' "$component_wat"

printf 'WASI HTTP response consume-body assembly passed\n'
