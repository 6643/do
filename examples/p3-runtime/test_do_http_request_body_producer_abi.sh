#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
wit="$repo_root/examples/p3-runtime/wit/http-request-body-producer-probe.wit"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/do-p3-http-request-body-producer-abi.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

# The producer uses the pinned CLI stdout stream ABI to create the universal
# stream pair.  Build a temporary WIT package so the CLI dependency is resolved
# from the repository's pinned snapshot rather than from a guessed standalone
# interface.
wit_dir="$tmp_dir/wit-package"
mkdir -p "$wit_dir"
cp -R "$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps" "$wit_dir/"
cp "$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps.toml" "$wit_dir/"
cp "$repo_root/src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps.lock" "$wit_dir/"
cat >"$wit_dir/worlds.wit" <<'WIT'
package wasi:http@0.3.0-rc-2025-09-16;

interface types {
  variant error-code { dns-timeout }
  resource fields { constructor(); }
  resource request {
    new: static func(
      headers: fields,
      contents: option<stream<u8>>,
      trailers: future<result<option<fields>, error-code>>,
      options: option<request-options>
    ) -> tuple<request, future<result<_, error-code>>>;
  }
  request-new-payload: func(
    headers: fields,
    contents: option<stream<u8>>,
    trailers: future<result<option<fields>, error-code>>,
    options: option<request-options>
  ) -> tuple<request, future<result<_, error-code>>>;
  resource request-options {}
  resource response {}
}

interface client {
  use types.{request, response, error-code};
  send: async func(request: request) -> result<response, error-code>;
}

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

core_wat="$tmp_dir/producer.wat"
core_wasm="$tmp_dir/producer.wasm"
embedded="$tmp_dir/producer.embedded.wasm"
component="$tmp_dir/producer.component.wasm"
wrong_wat="$tmp_dir/producer-wrong.wat"
wrong_wasm="$tmp_dir/producer-wrong.wasm"
wrong_embedded="$tmp_dir/producer-wrong.embedded.wasm"
wrong_component="$tmp_dir/producer-wrong.component.wasm"
wrong_output="$tmp_dir/producer-wrong.out"

test -f "$wit"
grep -Fq 'contents: option<stream<u8>>' "$wit"
grep -Fq 'run: async func() -> result<response, error-code>' "$wit"

cat >"$core_wat" <<'WAT'
(module
  (type $async-lower-send (func (param i32 i32) (result i32)))
  (type $fields-new (func (result i32)))
  (type $request-new (func (param i32 i32 i32 i32 i32 i32 i32)))
  (type $future-new (func (result i64)))
  (type $future-write (func (param i32 i32) (result i32)))
  (type $future-drop (func (param i32)))
  (type $stream-new (func (result i64)))
  (type $stream-io (func (param i32 i32 i32) (result i32)))
  (type $stream-drop (func (param i32)))
  ;; This ABI probe keeps a one-case error-code so the export task-return has
  ;; the minimal two-word response/error shape; the full HTTP error layout is
  ;; already pinned by the existing service probe.
  (type $task-return (func (param i32 i32)))
  (type $root-noargs (func))
  (type $root-new (func (result i32)))
  (type $root-wait (func (param i32 i32) (result i32)))
  (type $root-join (func (param i32 i32)))
  (type $root-cancel (func (param i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))

  (import "wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"
    (func $send (type $async-lower-send)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[constructor]fields"
    (func $fields-new (type $fields-new)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[static]request.new"
    (func $request-new (type $request-new)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[future-new-1]request-new-payload"
    (func $future-new (type $future-new)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[future-write-1]request-new-payload"
    (func $future-write (type $future-write)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[future-drop-writable-1]request-new-payload"
    (func $future-drop (type $future-drop)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request"
    (func $request-drop (type $future-drop)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]response"
    (func $response-drop (type $future-drop)))

  ;; Guest-created stream operations use the pinned CLI stdout descriptor;
  ;; the stream handles remain universal Component stream values.
  (import "wasi:cli/stdout@0.3.0-rc-2025-09-16" "[stream-new-0]write-via-stream"
    (func $stream-new (type $stream-new)))
  (import "wasi:cli/stdout@0.3.0-rc-2025-09-16" "[async-lower][stream-write-0]write-via-stream"
    (func $stream-write (type $stream-io)))
  (import "wasi:cli/stdout@0.3.0-rc-2025-09-16" "[stream-drop-readable-0]write-via-stream"
    (func $stream-drop-readable (type $stream-drop)))
  (import "wasi:cli/stdout@0.3.0-rc-2025-09-16" "[stream-drop-writable-0]write-via-stream"
    (func $stream-drop-writable (type $stream-drop)))

  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $root-noargs)))
  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $root-noargs)))
  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $root-noargs)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $root-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $root-wait)))
  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $root-wait)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $future-drop)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $root-join)))
  (import "$root" "[thread-yield]" (func $thread-yield (type $root-new)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (type $future-drop)))
  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $root-cancel)))
  (import "$root" "[context-get-0]" (func $context-get-0 (type $root-new)))
  (import "$root" "[context-set-0]" (func $context-set-0 (type $future-drop)))
  (import "[export]wasi:http/probe@0.3.0-rc-2025-09-16" "[task-return]run"
    (func $task-return (type $task-return)))

  (memory (export "memory") 0)
  (func (export "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run")
    (result i32) (i32.const 0))
  (func (export "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run")
    (param i32 i32 i32) (result i32) (i32.const 0))
  (func (export "cabi_realloc") (type $cabi-realloc) (i32.const 0))
  (func (export "_initialize") (type $root-noargs))
)
WAT

for import_name in \
  '[stream-new-0]write-via-stream' \
  '[async-lower][stream-write-0]write-via-stream' \
  '[stream-drop-readable-0]write-via-stream' \
  '[stream-drop-writable-0]write-via-stream'; do
  grep -Fq "\"$import_name\"" "$core_wat"
done

wasm-tools parse "$core_wat" -o "$core_wasm"
wasm-tools component embed "$wit_dir" "$core_wasm" \
  --world http-request-body-producer-probe -o "$embedded"
wasm-tools component new "$embedded" -o "$component"
wasm-tools validate --features cm-async,cm-more-async-builtins "$component"

sed 's/\[stream-new-0\]write-via-stream/[stream-new-0]wrong-stream/' \
  "$core_wat" >"$wrong_wat"
wasm-tools parse "$wrong_wat" -o "$wrong_wasm"
wasm-tools component embed "$wit_dir" "$wrong_wasm" \
  --world http-request-body-producer-probe -o "$wrong_embedded"
if wasm-tools component new "$wrong_embedded" -o "$wrong_component" >"$wrong_output" 2>&1; then
  printf 'unregistered root stream import unexpectedly assembled\n' >&2
  exit 1
fi
grep -Fq 'failed to resolve import' "$wrong_output"
grep -Fq '[stream-new-0]wrong-stream' "$wrong_output"

printf 'WASI HTTP request body producer ABI surface passed\n'
