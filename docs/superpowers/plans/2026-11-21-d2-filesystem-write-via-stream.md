# D2 `descriptor.write-via-stream` Implementation Plan

Date: 2026-11-21
Design: `doc/superpowers/specs/2026-11-21-d2-filesystem-write-via-stream-design.md`
Execution: native

## Outcome

Admit one private bounded filesystem writer route under
`--p3-async-component`:

```do
write_via_stream = @host_async_func(
    "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "descriptor.write-via-stream",
    (File, StreamWriter<u8>, u64) -> Result<nil, FileError>,
)
```

The positive fixture creates `new_stream<u8>(1)`, registers
`defer close(writer)`, starts the method with a `File` and `u64` offset,
performs a fixed bounded literal write, awaits the write and the method
completion, and returns `nil`. The generated Core WAT uses the measured method
ABI and omits the unused `stream.forward` operation so the current toolchain
can assemble the compiler route. Any shape outside this contract remains
rejected.

## Facts already pinned

- Upstream WIT hash:
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`.
- Method import:
  `[async-lower][method]descriptor.write-via-stream`.
- Method Core signature:
  `(i32 descriptor, i32 stream-writer, i64 offset, i32 result-area) -> i32`.
- Stream imports are method-scoped and include new, cancel-read,
  cancel-write, drop-readable, drop-writable, forward, stream-read, and
  stream-write. The compiler route uses all measured operations except the
  unneeded forward import.
- `defer close(writer)` is the source-level exactly-once writer termination.
- Writer and method errors are observed by the controlled Rust host. The Do
  probe returns `nil` and does not map `StreamError` into `FileError`.
- The standard dummy `stream.forward` assembly is currently rejected by
  wasm-tools/Wasmtime; the compiler-generated route is the executable gate.

## Scope and dependencies

The work is sequential because registry admission, target selection, emitter
layout, and runtime validation all depend on the previous interface. The ABI
snapshot is already present in the working tree and is the first gate.

## Task 1: Keep the ABI snapshot as a red/green gate

**Files:**

- Existing: `examples/p3-runtime/test_d2_wasi_filesystem_write_via_stream_abi.sh`
- Existing: `examples/p3-runtime/wit/wasi-filesystem-write-via-stream-probe.wit`
- Existing: `examples/p3-runtime/wit/wasi-filesystem-write-via-stream-cancel-probe.wit`
- Existing: `examples/p3-runtime/wasi-filesystem-write-via-stream.core.wat`
- Existing: `examples/p3-runtime/wasi-filesystem-write-via-stream-cancel.core.wat`

- [x] Run the script before fixtures and record the expected missing-input
  failure.
- [x] Add the pinned WIT mirrors, canonical snapshots, hashes, and exact import
  assertions.
- [x] Run the script and confirm the snapshot passes while explicitly recording
  standard `stream.forward` assembly as deferred.

## Task 2: Add a fail-closed manifest shape

**Files:**

- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Test: `src/build/p3_async_manifest.zig` unit tests

- [x] Add `filesystem_byte_stream_writer` to `LoweringShape` with a dedicated
  `FilesystemByteStreamWriterShape` record. Store the descriptor receiver,
  `u64` offset parameter, `stream<u8>` element, measured method operation,
  measured stream operations, task-return completion, and descriptor-drop
  import.
- [x] Validate the exact locator, member, `async` effect, parameters
  `[descriptor, stream<u8>, filesize]`, result
  `Result<nil,error-code>`, upstream WIT hash, method Core types
  `[i32,i32,i64,i32] -> [i32]`, task-return `(i32,i32)`, and method-scoped
  import names.
- [x] Require stream new/cancel/drop/read/write signatures from the measured
  registry record. Preserve `stream.forward` as evidence in the registry but
  do not make the compiler route import it.
- [x] Add one positive descriptor test and negative tests for changed method
  name, parameter order, non-byte stream, wrong result, missing task-return,
  and changed operation name.
- [x] Update the JSON registry with only the measured descriptor and run the
  manifest test to confirm unknown or drifted shapes return no lowering shape.

## Task 3: Add target admission before production lowering

**Files:**

- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/codegen_component_wasi_filesystem_write_via_stream.zig`
- Test: `src/build/codegen_component_async.zig` unit tests

- [x] Add a distinct target enum for the filesystem writer route.
- [x] Detect only `@host_async_func` with the exact `File,
  StreamWriter<u8>,u64` signature and run a method-specific source plan.
- [x] Route only this target to the new emitter and WIT generator. Keep the
  default generic async route fail-closed and keep CLI `stream_writer`
  selection unchanged.
- [x] Add analyzer tests for the positive fixture and rejection of an alias
  with the wrong locator/member, `StreamWriter<u32>`, `u32` offset, a second
  host binding, or an unrelated async function.

## Task 4: Define the bounded source grammar and write failing compiler fixtures

**Files:**

- Create: `src/build/test/compile_ok/821_wasi_filesystem_write_via_stream_component.do`
- Create: `src/build/test/compile_ok/821_wasi_filesystem_write_via_stream_component.expect`
- Create: numbered `compile_err` fixtures for wrong signature, missing defer,
  unfinalized writer, missing write await, second write, and wrong completion
  type.
- Modify: `src/build/test/test_harness.zig` for the new positive and negative
  cases.

- [x] Write the positive fixture before implementing the emitter. It must use
  one `File` resource, one `u64` offset, one `new_stream<u8>(1)`, one
  `defer close(writer)`, one literal `u8` write and await, one method await,
  and `run(...) -> nil`.
- [x] Run the compile fixture and confirm it fails with the unsupported target
  diagnostic.
- [x] Add the negative fixtures and confirm each fails for the intended
  admission reason rather than a parser error.

## Task 5: Implement the dedicated writer frame and WAT template

**Files:**

- Create: `src/build/wasi_filesystem_write_via_stream_component_template.wat`
- Modify: `src/build/codegen_component_wasi_filesystem_write_via_stream.zig`
- Modify: `src/build/build.zig` or the Zig embed list if required by the
  template registration.

- [x] Define a frame with waitable set, descriptor, stream reader/writer
  handles, method completion state, one write future/result slot, offset,
  result area, phase, and cleanup status.
- [x] Emit the measured method import with Core signature
  `(i32,i32,i64,i32)->i32`, method-scoped stream new/cancel/drop/read/write
  imports, descriptor drop, waitable/context imports, task-return, and
  cancellation imports. Do not emit `stream.forward` or a generic fallback.
- [x] Emit the state transitions in this order: acquire stream, register
  deferred writer close, start the filesystem method, perform the bounded
  write, await the write result, close the writer exactly once through the
  deferred cleanup path, await method completion, and finalize descriptor and
  frame.
- [x] Make cancellation phase-aware: cancel a pending stream write or method
  task, release live stream/future/descriptor handles once, and return through
  the cancellation task-return path. Do not claim external write rollback.
- [x] Add WAT marker assertions for method argument order, `u64` offset,
  result-area handling, `defer close` cleanup, no `stream.forward`, and
  exactly-once drop paths.
- [x] Run the positive fixture and confirm it now reaches WAT generation; then
  run the negative fixtures and confirm they remain rejected.

## Task 6: Generate and assemble the compiler WIT/Core route

**Files:**

- Modify: `src/build/codegen_component_wasi_filesystem_write_via_stream.zig`
- Test: `examples/p3-runtime/test_do_wasi_filesystem_write_via_stream_lowering.sh`
- Create: `examples/p3-runtime/wit/wasi-filesystem-write-via-stream-generated.wit`
  only if the repository convention requires a checked-in WIT snapshot.

- [x] Generate the package with filesystem `types` and `probe` interfaces,
  resource `descriptor`, method `write-via-stream`, and `run`/`cancel` async
  exports matching the positive source fixture.
- [x] Compile the fixture, parse Core WAT, embed the generated WIT, create a
  component, and run `validate-component --features component-async`.
- [x] Assert the assembled component contains the filesystem method import,
  stream lifecycle imports, task-return and resource-drop, and no
  `stream.forward` import or instruction.
- [x] Preserve the ABI snapshot script as a separate standard-WIT evidence
  gate; it must not be replaced by compiler-generated output.

## Task 7: Add the controlled Rust/Wasmtime lifecycle gate

**Files:**

- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_write_via_stream.rs`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_write_via_stream.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only if a new
  feature is required.

- [x] Implement a controlled `Descriptor` provider and a stream consumer that
  records method calls, offsets, accepted bytes, pending polls, stream write
  errors, completion errors, stream/future drops, descriptor drops, and
  `ResourceTable` state.
- [x] Run ready, pending, sink-error, method-error, cancel-before-completion,
  cancel-after-close, early store drop, and repeat modes.
- [x] Assert every completed route drops writer state, method completion state,
  and descriptor exactly once. For early store drop, stop assertions at store
  disposal and assert no post-disposal access.
- [x] Assert the controlled host sees the selected `u64` offset and bounded
  byte sequence. Do not use these tests to claim real OS file mutation.

## Task 8: Full regression and documentation synchronization

**Files:**

- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/master_plan.md`
- Modify: `CHANGELOG.md`

- [x] Record the new private capability, exact WIT hash, measured Core ABI,
  compiler route status, and the `stream.forward` toolchain limitation.
- [x] Remove this route from the pending list only after the compiler-generated
  assembly and Rust/Wasmtime lifecycle gate pass.
- [x] Run the ABI probe, focused Zig tests, focused compile/runtime scripts,
  `./src/build/test/run_tests.sh`, ReleaseSmall build, and release smoke.

## Review focus

1. Method call with an offset and stream handle in the wrong order: assert the
   Core import and generated call use descriptor, writer, offset, result area.
2. Writer error while the filesystem completion is still pending: assert no
   duplicate close/drop and no use-after-disposal.
3. Cancellation after bytes were accepted: assert cleanup without claiming
   filesystem rollback.
4. Descriptor drop during early store disposal: assert no post-disposal host
   access and no invalid final table assertion.
5. Standard WIT `stream.forward` drift or toolchain enablement change: assert
   the snapshot records the change and the compiler route remains explicitly
   gated.

## Plan self-review

- Every design goal has an owning task: ABI facts (1), fail-closed admission
  (2-4), lifecycle emitter (5), assembly (6), runtime matrix (7), and status
  synchronization (8).
- The plan keeps the method-specific route separate from generic stream and
  filesystem lowering.
- The only unresolved external fact is toolchain support for standard
  `stream.forward`; the plan makes it a measured gate and does not infer
support from the dummy template.
