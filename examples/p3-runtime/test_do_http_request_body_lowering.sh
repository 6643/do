#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
fixture="$repo_root/examples/p3-runtime/http-request-body.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-body-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/body.wat"
core_wasm="$tmp_dir/body.wasm"
embedded="$tmp_dir/body.embedded.wasm"
component="$tmp_dir/body.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

grep -Fq '"wasi:cli/stdin@0.3.0-rc-2025-09-16" "read-via-stream"' "$core_wat"
grep -Fq '"wasi:http/types@0.3.0-rc-2025-09-16" "[static]request.new"' "$core_wat"
grep -Fq '"wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"' "$core_wat"
grep -Fq '"wasi:cli/stdin@0.3.0-rc-2025-09-16" "[future-drop-readable-1]read-via-stream"' "$core_wat"
grep -Fq 'call $body-acquire' "$core_wat"
grep -Fq 'call $construct-request' "$core_wat"
grep -Fq 'call $drop-body-completion' "$core_wat"
grep -Fq 'i32.const 1' "$core_wat"
if grep -Fq 'async-lower][request.new]' "$core_wat"; then
  printf 'request.new unexpectedly lowered as a synchronous call\n' >&2
  exit 1
fi

wasm-tools parse "$core_wat" -o "$core_wasm"
cat >>"$wit_dir/worlds.wit" <<'WIT'

interface probe {
  use types.{response, error-code};
  run: async func() -> result<response, error-code>;
}

world http-request-body-probe {
  import types;
  import client;
  import wasi:cli/stdin@0.3.0-rc-2025-09-16;
  export probe;
}
WIT
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world http-request-body-probe --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

printf 'WASI HTTP request body lowering passed\n'
