#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
do_bin="$repo_root/bin/do"
fixture="$repo_root/examples/p3-runtime/http-request-body-producer-send-first.do"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-body-producer-lowering.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

wit_dir="$tmp_dir/wit-package"
core_wat="$tmp_dir/producer.wat"
core_wasm="$tmp_dir/producer.wasm"
embedded="$tmp_dir/producer.embedded.wasm"
component="$tmp_dir/producer.component.wasm"

DO_LIB_ROOT="$repo_root/lib" "$do_bin" build "$fixture" \
  --p3-async-component --p3-wit-package-output "$wit_dir" -o "$core_wat"

for import_name in \
  '"wasi:cli/stdout@0.3.0-rc-2025-09-16" "[stream-new-0]write-via-stream"' \
  '"wasi:cli/stdout@0.3.0-rc-2025-09-16" "[async-lower][stream-write-0]write-via-stream"' \
  '"wasi:cli/stdout@0.3.0-rc-2025-09-16" "[stream-drop-writable-0]write-via-stream"' \
  '"wasi:http/types@0.3.0-rc-2025-09-16" "[static]request.new"' \
  '"wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"'; do
  grep -Fq "$import_name" "$core_wat"
done

grep -Fq 'call $start-producer' "$core_wat"
grep -Fq 'call $construct-producer-request' "$core_wat"
grep -Fq 'call $start-producer-send' "$core_wat"
grep -Fq '[future-drop-readable-2]request-new-payload' "$core_wat"
grep -Fq '(export "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run")' "$core_wat"

request_line=$(awk '/\(func \$construct-producer-request/{inside=1} inside && /call \$producer-request-new/{print NR; exit}' "$core_wat")
close_line=$(awk '/\(func \$start-producer-write/{inside=1} inside && /call \$producer-stream-drop-writable/{print NR; exit}' "$core_wat")
test -n "$request_line" -a -n "$close_line"
test "$request_line" -lt "$close_line"

wasm-tools parse "$core_wat" -o "$core_wasm"
cat >>"$wit_dir/worlds.wit" <<'WIT'

interface probe {
  use types.{response, error-code};
  run: async func() -> result<response, error-code>;
}

world http-request-body-producer-probe {
  import types;
  import client;
  import wasi:cli/stdout@0.3.0-rc-2025-09-16;
  export probe;
}
WIT
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world http-request-body-producer-probe \
  --features cm-async,cm-more-async-builtins -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

printf 'WASI HTTP request body producer lowering passed\n'
