# Parameterized Stream Writer Helper Reordered Arguments Implementation Plan

> **For agentic workers:** Execute this plan inline with focused red/green verification. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit one bounded parameterized stream-writer helper whose declaration and call order may be reordered by semantic parameter type.

**Architecture:** Parse exactly three helper parameter kinds (`StreamWriter<u8>`, `u64`, `u8`) into an explicit order. Validate each helper call argument against the source identifier selected by that kind, while preserving the existing semantic `writer/count/value` fields consumed by the descriptor-specific emitter. Keep all root ABI and unsupported-shape rejection boundaries unchanged.

**Tech Stack:** Zig compiler unit tests, WAT Component emitter, pinned `wasm-tools 1.254.0`, Rust/Wasmtime runtime fixtures, shell harnesses, JSON registry.

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Root producer parameters remain `(count u64, value u8)`.
- Accept exactly one `StreamWriter<u8>`, one `u64`, and one `u8` helper parameter.
- Reject literal, duplicate, missing, extra, unsupported, and third-hop forwarding arguments.
- Preserve the current frame layout, WIT signature, lease cleanup, and descriptor-specific lowering.
- Do not commit, push, reset, clean, or revert unrelated dirty worktree changes.

---

### Task 1: Add red and negative parser tests

**Files:**
- Modify: `src/build/codegen_component_async_plan.zig` near the parameterized helper tests

- [x] **Step 1: Add a positive reordered direct-helper test.**

Use a helper declared as `(count u64, writer StreamWriter<u8>, value u8)` and
called as `finish_stream(count, writer, value)`. Assert that
`StreamWriterPlan.analyze` returns `ProducerMode.countdown`, helper name
`finish_stream`, and semantic `count`/`value` names.

- [x] **Step 2: Change the old reordered-argument rejection to a literal rejection.**

Keep the same exact helper shape but call it with `finish_stream(writer, 7,
value)`. Continue to expect `error.UnsupportedP3StreamWriterComponent`.

- [x] **Step 3: Run the focused plan tests and verify RED.**

Run:

```bash
cd src && zig test build/codegen_component_async_plan.zig --test-filter 'parameterized producer helper'
```

Expected: the new reordered positive test fails because the current parser
requires positional `(writer, count, value)` parameters; the literal negative
test remains green.

### Task 2: Implement typed helper parameter-order parsing

**Files:**
- Modify: `src/build/codegen_component_async_plan.zig` around `ParameterizedStreamWriterFunction` and `find_parameterized_stream_writer_function_named`

- [x] **Step 1: Add an internal parameter-kind enum and order field.**

Represent the three accepted kinds as `writer`, `count`, and `value`, and store
`[3]ParameterizedParameterKind` in each parsed helper.

- [x] **Step 2: Parse exactly three comma-separated typed parameters.**

Recognize `StreamWriter<u8>`, `u64`, and `u8` in any order. Reject duplicate
kinds, missing kinds, unsupported types, extra parameters, malformed return
types, and malformed bodies. Preserve each kind's identifier in the existing
`writer_name`, `count_name`, and `value_name` fields.

- [x] **Step 3: Validate calls against the callee kind order.**

Resolve the callee before accepting its three call arguments. For each formal
kind, require the corresponding source identifier (`writer_name`, `count_name`,
or `value_name`) and require an identifier token, so literals and arbitrary
expressions remain rejected. Require the closing `)` immediately after the
third argument.

- [x] **Step 4: Run the focused tests and verify GREEN.**

Run the same `zig test` command from Task 1. Expected: reordered direct helper
passes, literal rejection passes, and all existing parameterized helper,
forwarding, and third-hop tests remain green.

### Task 3: Add reordered forwarding lowering/runtime evidence

**Files:**
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_component_stream_writer.zig`
- Create: `examples/p3-runtime/stream-probe-guest-producer-parameterized-reordered-helper.do`
- Create: `examples/p3-runtime/wit/stream-probe-guest-producer-parameterized-reordered-helper.wit`
- Create: `examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_reordered_helper.sh`
- Create: `examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_reordered_helper.sh`
- Reuse: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs` with its existing `parameterized-helper` mode

- [x] **Step 1: Add an emitter assertion for reordered semantic mapping.**

Use a final helper declared `(value u8, writer StreamWriter<u8>, count u64)`
and called in that formal order. Assert the generated WAT still uses the
existing `(i64, i32)` root export, frame offsets `52/60`, and one root export.

- [x] **Step 2: Add the Do fixture and exact WIT sidecar.**

Keep the existing private `do:stream-probe` descriptor and change only helper
formal/call order. The sidecar must remain byte-for-byte equal to the existing
stream writer WIT shape.

- [x] **Step 3: Extend the Rust runner with a reordered-helper mode.**

Reuse pending, ready, and `Err(pipe)` modes and require count `0/1/3`, value
`90`, ordered bytes, one host callback, one stream drop, and empty resource
table.

- [x] **Step 4: Run the focused lowering/runtime scripts.**

Run:

```bash
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_reordered_helper.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_reordered_helper.sh
```

Expected: Component validation and all three Rust/Wasmtime completion modes
pass.

### Task 4: Synchronize boundary documentation and run release gates

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [x] **Step 1: Record the accepted reordered-helper shape and exclusions.**

State that only the three typed parameters may be reordered; literals,
arbitrary expressions, extra hops, and general producer/resource shapes remain
rejected.

- [x] **Step 2: Run focused and repository verification.**

Run:

```bash
cd src && zig test build/codegen_component_async_plan.zig --test-filter 'parameterized producer'
cd src && zig test build/codegen_component_stream_writer.zig --test-filter 'parameterized'
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_reordered_helper.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_reordered_helper.sh
cd src && zig test main.zig
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
bash src/build/test/run_release_smoke.sh
zig fmt --check src/build/codegen_component_async_plan.zig src/build/codegen_component_stream_writer.zig
rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_reordered_helper.sh examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_reordered_helper.sh
jq empty src/build/p3_async_registry.json
git diff --check
```

- [x] **Step 3: Update plan status only from green evidence.**

Mark this plan complete after all focused, runtime, regression, formatting,
shell, JSON, and diff checks pass. Do not claim general async lowering or
borrowed-resource support.
