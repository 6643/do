#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_root=${TMPDIR:-"$repo_root/.tmp/do-tmp"}
mkdir -p "$tmp_root"
tmp_dir=$(mktemp -d "$tmp_root/stream-mirror.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

fixture="$repo_root/examples/p3-runtime/stream-probe-stream-mirror.do"
expected_wit="$repo_root/examples/p3-runtime/wit/stream-probe-stream-mirror.wit"
wit_path="$tmp_dir/stream-mirror.wit"
core_wat="$tmp_dir/stream-mirror.wat"
core_wasm="$tmp_dir/stream-mirror.wasm"
component_path="$tmp_dir/stream-mirror.component.wasm"
ordinary_output="$tmp_dir/ordinary.wat"
ordinary_log="$tmp_dir/ordinary.log"

DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build --p3-async-component \
  --p3-wit-output "$wit_path" "$fixture" -o "$core_wat"
cmp "$wit_path" "$expected_wit"

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools validate --features gc,cm-async,cm-more-async-builtins "$core_wasm"
TMPDIR="$tmp_root" bash "$repo_root/examples/p3-runtime/assemble_async_component.sh" \
  "$wit_path" "$core_wasm" stream-mirror-probe "$component_path"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component_path"

grep -Fq '[stream-mirror-source-read]' "$core_wat"
grep -Fq '[stream-mirror-writer-write]' "$core_wat"
grep -Fq '[stream-mirror-sink-result]' "$core_wat"
grep -Fq '[stream-mirror-cancel]' "$core_wat"
grep -Fq '[stream-mirror-source-cancel] future-drop-readable' "$core_wat"
grep -Fq '[stream-mirror-frame-size] 96' "$core_wat"
grep -Fq 'do:stream-probe/source@0.1.0' "$core_wat"
grep -Fq '[future-drop-readable-1]read-via-stream' "$core_wat"
grep -Fq '(export "[async-lift]produce")' "$core_wat"
if grep -Fq '[async-lift]write-via-stream' "$core_wat"; then
  printf 'stream mirror leaked the sink helper export\n' >&2
  exit 1
fi

if DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build "$fixture" -o "$ordinary_output" >"$ordinary_log" 2>&1; then
  printf 'ordinary do build unexpectedly lowered the async fixture\n' >&2
  exit 1
fi
grep -Fq 'AsyncLoweringUnavailable' "$ordinary_log"

printf 'stream mirror Do lowering gate passed\n'
