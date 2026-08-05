#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
fixture="$repo_root/examples/p3-runtime/http-request-body-await-completion.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-body-await-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/body.wat"
core_wasm="$tmp_dir/body.wasm"
embedded="$tmp_dir/body.embedded.wasm"
component="$tmp_dir/body.component.wasm"
guard_output="$tmp_dir/ordinary-build.out"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

if DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" -o "$tmp_dir/ordinary.wat" >"$guard_output" 2>&1; then
  printf 'ordinary do build unexpectedly lowered the await fixture\n' >&2
  exit 1
fi
grep -Fq 'AsyncLoweringUnavailable' "$guard_output"

grep -Fq '"wasi:cli/stdin@0.3.0-rc-2025-09-16" "[async-lower][future-read-1]read-via-stream"' "$core_wat"
grep -Fq 'call $start-body-request' "$core_wat"
grep -Fq 'call $start-body-completion' "$core_wat"
grep -Fq 'call $accept-body-completion' "$core_wat"
grep -Fq 'struct.set $async-frame $slot-body-completion-result' "$core_wat"
grep -Fq 'struct.set $async-frame $slot-body-request' "$core_wat"
grep -Fq 'i32.const 48' "$core_wat"
if grep -Fq 'call $acquire-body' "$core_wat" && grep -Fq 'call $construct-request' "$core_wat"; then
  :
else
  printf 'await lowering is missing the staged body acquisition/constructor path\n' >&2
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

printf 'WASI HTTP request body completion await lowering passed\n'
