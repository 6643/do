# Task 9 StreamMirror WAT validity fix report

## Result

Fixed the StreamMirror source import replacement boundary so the generated
Core WAT contains exactly one closing quote for the `[task-cancel]` import.
Source and sink import contracts and admission behavior are unchanged.

## TDD evidence

Added assertions to `stream mirror lowering emits source and writer callback states`
before changing production code:

- malformed `"[task-cancel]""` must be absent;
- `(import "[export]$root" "[task-cancel]" (func $task-cancel` must be present.

The focused test failed first at the malformed-WAT assertion with
`error.TestUnexpectedResult` at line 3804, confirming the regression test
detected the existing bug.

## Implementation

Changed only the `source_import_insertion` replacement text in
`src/build/codegen_component_stream_writer.zig`: the replacement now stops
before the closing quote, leaving the quote already present in the original
boundary exactly once.

## Verification

- `zig test build/codegen_component_stream_writer.zig --test-filter 'stream mirror lowering emits source and writer callback states'`: passed.
- `cd src && zig build`: passed (rebuilt `bin/do` for script verification).
- `bash examples/p3-runtime/test_do_stream_mirror_lowering.sh`: passed.
- `bash examples/p3-runtime/test_rust_stream_mirror.sh`: passed; pending, ready, source-eof, error, cancel, and early-drop modes passed.
- `cd src && zig test build/codegen_component_stream_writer.zig`: passed, 254/254 tests.

## Concerns

No known concerns within the requested scope. The first script run before
rebuilding `bin/do` used the stale executable and reproduced the old malformed
WAT; after the standard rebuild both runtime scripts passed.
