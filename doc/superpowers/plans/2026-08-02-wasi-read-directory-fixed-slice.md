# WASI Read-Directory Fixed Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a fixed `descriptor.read-directory` Component slice that acquires one directory stream, reads one `directory-entry`, awaits its completion future, and performs exactly-once stream/future/resource cleanup.

**Architecture:** Extend the pinned async manifest with a dedicated record-stream shape that is admitted only for `wasi:filesystem/types@0.3.0-rc-2025-09-16/descriptor.read-directory`. Add a fixed source-plan/emitter path for one directory resource and one bounded read; keep generic record-stream lowering, public ownership syntax, dynamic loops, and arbitrary filesystem methods rejected. Validate the generated Component with the pinned WIT package and execute it in Wasmtime with a Rust host that records entry payloads and cleanup counts.

**Tech Stack:** Zig compiler modules, pinned `wasm-tools 1.254.0`, WAT/WIT Component async ABI, Rust Wasmtime host runner.

## Global Constraints

- Keep `own<T>`, `borrow<T>`, `ref<T>`, pointers, and references out of Do source syntax.
- Admit only the pinned `descriptor.read-directory` locator/member and exact canonical import names/signatures.
- Support one fixed directory stream read and one completion await; reject loops, multiple readers, arbitrary stream sources, payload-bearing errors, and other filesystem async methods.
- Preserve exactly-once cleanup for the directory resource, stream readable, stream completion future, and future result storage.
- Do not implement rollback of external effects on cancellation.
- Work in the existing dirty checkout; do not reset, clean, commit, or push.

---

### Task 1: Admit the Exact Record-Stream Descriptor

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/codegen_component_async.zig`
- Test: `src/build/p3_async_manifest.zig`
- Test: `src/build/sema_imports.zig`
- Test: `src/build/codegen_component_async.zig`

**Interfaces:**
- Consumes: The frozen ABI from `examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh`.
- Produces: `LoweringShape.record_stream_reader` with `directory-entry` element, stream index `0`, future index `1`, and all pinned stream/future operations.

- [x] **Step 1: Write the failing manifest test.**

Add a checked-in descriptor fixture to the registry test that expects:

```zig
const descriptor = registry.find(
    "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "descriptor.read-directory",
) orelse return error.TestUnexpectedResult;
const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
    .record_stream_reader => |value| value,
};
try std.testing.expectEqualStrings("directory-entry", shape.element);
try std.testing.expectEqual(@as(usize, 0), shape.stream_index);
try std.testing.expectEqual(@as(usize, 1), shape.future_index);
```

- [x] **Step 2: Run the focused test and verify RED.**

Run `cd src && zig test build/p3_async_manifest.zig`. It must fail because the registry descriptor and `LoweringShape.record_stream_reader` admission do not exist.

- [x] **Step 3: Add the exact registry entry and lowering shape.**

Add the observed locator/member with `effect = "record-stream-reader"`, result `tuple<stream<directory-entry>,future<result<_,error-code>>>`, result-area completion, method type `(i32,i32)->i32`, stream index `0`, future index `1`, and the exact import names from the ABI probe. Validate every operation signature before returning the new shape; keep `unsupported_shape()` as a compatibility evidence helper but make this pinned descriptor explicitly lowerable only through the new fixed target.

- [x] **Step 4: Add signature admission and target classification tests.**

Extend `sema_imports` to recognize only the exact source signature:

```
(Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>
```

Extend `codegen_component_async.Target` with `wasi_read_directory`; classify a fixture containing only the pinned descriptor as that target and reject a descriptor with a spoofed canonical import or a second stream source.

- [x] **Step 5: Run the focused green tests.**

Run:

```bash
cd src && zig test build/p3_async_manifest.zig
cd src && zig test build/sema_imports.zig
cd src && zig test build/codegen_component_async.zig
```

Expected: all tests pass and existing u8 stream/HTTP targets remain unchanged.

---

### Task 2: Parse the Fixed Source Flow

**Files:**
- Create: `src/build/codegen_component_wasi_filesystem_read_directory.zig`
- Modify: `src/build/codegen_component_async.zig`
- Test: `src/build/codegen_component_wasi_filesystem_read_directory.zig`
- Test: `src/build/codegen_component_async.zig`

**Interfaces:**
- Consumes: `LoweringShape.record_stream_reader` and the exact `Dir` host signature.
- Produces: `ReadDirectoryPlan.analyze(tokens, registry) !?ReadDirectoryPlan`.

- [x] **Step 1: Write failing plan tests.**

The positive fixture must contain one `Dir` parameter, one `read-directory(dir)` call returning the stream/future pair, one `@next(reader)` future whose item type is `DirectoryEntry`, one await of that future, one await of the completion future, and explicit drops before return. Add negative fixtures for a second `@next`, a loop, a non-pinned descriptor, and a payload-bearing completion error.

- [x] **Step 2: Run the plan tests and verify RED.**

Run `cd src && zig test build/codegen_component_wasi_filesystem_read_directory.zig`; it must fail because the plan module does not exist.

- [x] **Step 3: Implement guarded linear parsing.**

Implement `ReadDirectoryPlan.analyze` with early returns. Capture the directory argument, stream reader name, stream completion future name, entry future/result names, completion result name, and terminal drop order. Require `DirectoryEntry` exactly and reject all other source shapes.

- [x] **Step 4: Wire target dispatch.**

Route `Target.wasi_read_directory` through the new module in `emit_component_wat` and `emit_component_wit`; preserve the existing unsupported error for any unmatched source.

- [x] **Step 5: Run focused green tests.**

Run the module test and `zig test build/codegen_component_async.zig`.

---

### Task 3: Emit the One-Read Core ABI

**Files:**
- Modify: `src/build/codegen_component_wasi_filesystem_read_directory.zig`
- Create: `examples/p3-runtime/wasi-filesystem-read-directory.do`
- Create: `examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh`
- Test: `src/build/codegen_component_wasi_filesystem_read_directory.zig`

**Interfaces:**
- Consumes: `ReadDirectoryPlan`.
- Produces: Core WAT imports for the pinned method, stream operations, future operations, descriptor drop, and a Component WIT world containing the `directory-entry` record.

- [x] **Step 1: Add WAT assertions before emitter changes.**

Assert the generated output contains the exact method, stream index `0`, future index `1`, record result-area pointers, one stream read, one future read, and one drop for every owned handle. Assert a second read or missing cleanup is rejected.

- [x] **Step 2: Implement the bounded frame and result areas.**

Use explicit frame slots for directory resource, stream readable, stream completion future, stream-read result area, completion result area, and terminal cleanup flags. Pass the record result-area pointer to `stream-read`; preserve the two managed fields (`descriptor-type` scalar and string pointer/length) until the entry is consumed.

- [x] **Step 3: Emit the completion state machine.**

Read the directory entry once, await the entry future, await the independent completion future, then drop the stream readable, completion future, and directory resource exactly once on success, EOF, error, and cancellation paths.

- [x] **Step 4: Assemble and validate the Component.**

Run `wasm-tools parse`, `wasm-tools component embed`, `wasm-tools component new`, and `wasm-tools validate --features cm-async,cm-more-async-builtins`. Require the embedded `directory-entry` record to remain visible.

---

### Task 4: Execute the Rust/Wasmtime Vertical Slice

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_read_directory.rs`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_read_directory.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` only if the binary needs an explicit target entry

**Interfaces:**
- Consumes: The Component from Task 3.
- Produces: Runtime markers for one entry `name = "alpha"`, exact stream/future/resource drop counts, and `table-empty=true`.

- [x] **Step 1: Add host state and unit tests first.**

Model `directory-entry` as a descriptor type plus string, return one entry then EOF, expose a pending-once completion future and an immediately-ready mode, and assert the host state machine rejects double reads/drops.

- [x] **Step 2: Run the unit test and verify RED.**

Run `cargo test --bin do-p3-wasi-filesystem-read-directory-host-runner`; it must fail until the host state and binary are implemented.

- [x] **Step 3: Implement the Wasmtime host.**

Register a preopen directory resource, validate the borrowed/owned descriptor identity, serve one `alpha` entry, count stream readable/future/resource drops, and reject any residual `ResourceTable` entry.

- [x] **Step 4: Run both completion modes.**

The script must assert pending-once and ready modes, one entry payload, one EOF, exactly-once cleanup, and `table-empty=true`.

---

### Task 5: Documentation And Regression Closure

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `examples/p3-runtime/README.md`

**Interfaces:**
- Consumes: Task 4 runtime evidence.
- Produces: Accurate status: fixed read-directory slice implemented; generic record-stream and arbitrary resource methods remain unsupported.

- [x] **Step 1: Update the blocker boundary.**

Replace only the G6.2 line with the fixed-slice scope and list generic record streams, multiple entries/loops, payload errors, and arbitrary filesystem async methods as remaining unsupported.

- [x] **Step 2: Run the complete verification matrix.**

Run:

```bash
cd src && zig test main.zig
SKIP_BUILD=1 ./src/build/test/run_tests.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory.sh
bash src/build/test/run_release_smoke.sh
git diff --check
```

Expected: all commands exit 0; regression remains `pass=1049 fail=0 skip=3`.
