#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
toolchain_bin="${DO_TOOLCHAIN_BIN:-$repo_root/bin/do-toolchain}"
export DO_TOOLCHAIN_LOCK="${DO_TOOLCHAIN_LOCK:-$repo_root/toolchain/toolchain.lock.json}"
fixture="$repo_root/examples/p3-runtime/http-request-body-producer-write-error.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-body-producer-write-error.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/producer.wat"
core_wasm="$tmp_dir/producer.wasm"
embedded="$tmp_dir/producer.embedded.wasm"
component="$tmp_dir/producer.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

for marker in \
  '"wasi:cli/stdout@0.3.0-rc-2025-09-16" "[stream-new-0]write-via-stream"' \
  '"wasi:cli/stdout@0.3.0-rc-2025-09-16" "[async-lower][stream-write-0]write-via-stream"' \
  '"wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"' \
  '(type $task-return (func (param i32 i32)))' \
  'call $subtask-cancel' \
  'call $producer-stream-drop-writable' \
  'call $task-return'; do
  rg -Fq "$marker" "$core_wat"
done

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

printf 'WASI HTTP request body producer write-error lowering passed\n'
