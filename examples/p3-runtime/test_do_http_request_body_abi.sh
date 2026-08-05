#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/http-request-body-probe.wit"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-body-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

core_wat="$tmp_dir/request-body.wat"
core_wasm="$tmp_dir/request-body.wasm"
embedded="$tmp_dir/request-body.embedded.wasm"
component="$tmp_dir/request-body.component.wasm"
wrong_wat="$tmp_dir/request-body-wrong.wat"
wrong_wasm="$tmp_dir/request-body-wrong.wasm"
wrong_embedded="$tmp_dir/request-body-wrong.embedded.wasm"
wrong_component="$tmp_dir/request-body-wrong.component.wasm"
wrong_output="$tmp_dir/request-body-wrong.out"

test -f "$wit"
grep -Fq 'contents: option<stream<u8>>' "$wit"
grep -Fq 'acquire: func() -> tuple<stream<u8>, future<result<_, error-code>>>' "$wit"

# This is a canonical async Component core surface. The stream helper imports
# are deliberately referenced even though the probe does not execute a read;
# this freezes the toolchain's indexed names before lowering depends on them.
cat >"$core_wat" <<'WAT'
(module
  (type $run (func (result i32)))
  (type $callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (type $task-cancel (func))
  (type $waitable-new (func (result i32)))
  (type $waitable-wait (func (param i32 i32) (result i32)))
  (type $waitable-drop (func (param i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $subtask-cancel (func (param i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $stream-new (func (result i64)))
  (type $stream-cancel (func (param i32) (result i32)))
  (type $stream-drop (func (param i32)))
  (type $stream-read (func (param i32 i32 i32) (result i32)))

  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[constructor]fields"
    (func $fields-new (result i32)))
  ;; request.new's canonical ABI is seven i32 parameters:
  ;; fields, option<stream>, trailers future, and request options.
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[static]request.new"
    (func $request-new (param i32 i32 i32 i32 i32 i32 i32)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]fields"
    (func $fields-drop (param i32)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request"
    (func $request-drop (param i32)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request-options"
    (func $options-drop (param i32)))

  ;; The body source returns a stream/future pair through the result area.
  (import "wasi:http/body@0.3.0-rc-2025-09-16" "acquire"
    (func $body-acquire (param i32)))
  (import "wasi:http/body@0.3.0-rc-2025-09-16" "[stream-new-0]acquire"
    (func $stream-new-import (type $stream-new)))
  (import "wasi:http/body@0.3.0-rc-2025-09-16" "[stream-cancel-read-0]acquire"
    (func $stream-cancel-read-import (type $stream-cancel)))
  (import "wasi:http/body@0.3.0-rc-2025-09-16" "[stream-cancel-write-0]acquire"
    (func $stream-cancel-write-import (type $stream-cancel)))
  (import "wasi:http/body@0.3.0-rc-2025-09-16" "[stream-drop-readable-0]acquire"
    (func $stream-drop-read-import (type $stream-drop)))
  (import "wasi:http/body@0.3.0-rc-2025-09-16" "[stream-drop-writable-0]acquire"
    (func $stream-drop-write-import (type $stream-drop)))
  (import "wasi:http/body@0.3.0-rc-2025-09-16" "[async-lower][stream-read-0]acquire"
    (func $stream-read-import (type $stream-read)))
  (import "wasi:http/body@0.3.0-rc-2025-09-16" "[async-lower][stream-write-0]acquire"
    (func $stream-write-import (type $stream-read)))
  (import "wasi:http/body@0.3.0-rc-2025-09-16" "[future-drop-readable-1]acquire"
    (func $future-drop-import (type $resource-drop)))

  (import "[export]$root" "[task-cancel]"
    (func $task-cancel-import (type $task-cancel)))
  (import "$root" "[backpressure-inc]"
    (func $backpressure-inc (type $task-cancel)))
  (import "$root" "[backpressure-dec]"
    (func $backpressure-dec (type $task-cancel)))
  (import "$root" "[waitable-set-new]"
    (func $waitable-new-import (type $waitable-new)))
  (import "$root" "[waitable-set-wait]"
    (func $waitable-wait-import (type $waitable-wait)))
  (import "$root" "[waitable-set-poll]"
    (func $waitable-poll-import (type $waitable-wait)))
  (import "$root" "[waitable-set-drop]"
    (func $waitable-drop-import (type $waitable-drop)))
  (import "$root" "[waitable-join]"
    (func $waitable-join-import (type $waitable-join)))
  (import "$root" "[thread-yield]"
    (func $thread-yield-import (type $waitable-new)))
  (import "$root" "[subtask-drop]"
    (func $subtask-drop-import (type $resource-drop)))
  (import "$root" "[subtask-cancel]"
    (func $subtask-cancel-import (type $subtask-cancel)))
  (import "$root" "[context-get-0]"
    (func $context-get-import (type $waitable-new)))
  (import "$root" "[context-set-0]"
    (func $context-set-import (type $resource-drop)))
  (import "[export]wasi:http/probe@0.3.0-rc-2025-09-16" "[task-return]run"
    (func $task-return (type $task-cancel)))

  (func $run (type $run) (i32.const 0))
  (func $callback (type $callback) (i32.const 0))
  (func $cabi-realloc (type $cabi-realloc) (i32.const 0))
  (func $_initialize (type $task-cancel))
  (memory 0)
  (export "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run" (func $run))
  (export "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run" (func $callback))
  (export "memory" (memory 0))
  (export "cabi_realloc" (func $cabi-realloc))
  (export "_initialize" (func $_initialize))
)
WAT

for import_name in \
  '[static]request.new' \
  '[stream-new-0]acquire' \
  '[stream-cancel-read-0]acquire' \
  '[stream-cancel-write-0]acquire' \
  '[stream-drop-readable-0]acquire' \
  '[stream-drop-writable-0]acquire' \
  '[async-lower][stream-read-0]acquire' \
  '[async-lower][stream-write-0]acquire' \
  '[future-drop-readable-1]acquire'; do
  grep -Fq "\"$import_name\"" "$core_wat"
done
grep -Fq '(func $request-new (param i32 i32 i32 i32 i32 i32 i32))' "$core_wat"
grep -Fq '(func $body-acquire (param i32))' "$core_wat"

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit" "$core_wasm" \
  --world http-request-body-probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

# A guessed index/name must not be accepted as a stream operation. Component
# embed preserves the core import, while component new resolves it against the
# WIT interface and must reject it as an unregistered descriptor.
sed 's/\[stream-new-0\]acquire/[stream-new-0]body/' "$core_wat" >"$wrong_wat"
wasm-tools parse "$wrong_wat" -o "$wrong_wasm"
wasm-tools component embed "$wit" "$wrong_wasm" \
  --world http-request-body-probe -o "$wrong_embedded"
if wasm-tools component new "$wrong_embedded" -o "$wrong_component" >"$wrong_output" 2>&1; then
  printf 'unregistered body stream import unexpectedly assembled\n' >&2
  exit 1
fi
grep -Fq 'failed to resolve import' "$wrong_output"
grep -Fq '[stream-new-0]body' "$wrong_output"

printf 'WASI HTTP request body ABI surface passed\n'
