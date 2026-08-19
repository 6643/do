# Parameterized Stream-Writer Forwarding Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or inline execution in this session). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit one private forwarding helper that transfers `(StreamWriter<u8>, u64, u8)` to the existing parameterized countdown helper while preserving all general async-call rejection boundaries.

**Architecture:** Extend the descriptor-specific source-shape parser with a strict one-hop parameterized helper chain. Reuse the existing `StreamWriterPlan` countdown metadata and `(i64, i32)` emitter; generated Components still export only the root `produce` function.

**Tech Stack:** Zig compiler/WAT, pinned `wasm-tools 1.254.0`, Rust/Wasmtime `47.0.2`, existing `src/build/test/run_tests.sh` harness.

> **Status:** Complete. Focused parser/emitter tests, Component/Rust/Wasmtime
> gates, default/WASM regressions, ReleaseSmall smoke, formatting, shell syntax,
> and diff checks passed on 2026-08-03. General async/resource boundaries remain
> pending.

## Global Constraints

- The only accepted new chain is `produce -> forward_stream -> finish_stream`.
- Every edge transfers the exact direct names `(writer, count, value)` in that order.
- The forwarding helper performs only one awaited call and no writer operation, stream creation, branch, or second call.
- The final helper is the already verified `(StreamWriter<u8>, u64, u8)` zero-pre-guarded countdown shape.
- The compiler emits only root `[async-lift]produce`, with frame offsets `52` (`i64 count`) and `60` (`u8 value`).
- Public `own<T>`, `borrow<T>`, `ref<T>`, pointers, arbitrary producer expressions, third hops, borrowed/nested/variant resource fields, and arbitrary filesystem async methods remain rejected.
- Preserve all unrelated dirty-worktree changes; do not reset, clean, or overwrite them.

---

### Task 1: Red source-shape, plan, and emitter tests

**Files:**
- Create: `examples/p3-runtime/stream-probe-guest-producer-parameterized-forwarding-helper.do`
- Create: `src/build/test/check/401_stream_writer_parameterized_forwarding_helper.do`
- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_component_stream_writer.zig`

**Interfaces:**
- Consumes the verified parameterized helper fixture and `StreamWriterPlan` countdown metadata.
- Produces a failing accepted-shape assertion plus negative argument-order and third-hop cases.

- [x] **Step 1: Add the exact three-function source fixture and check fixture.**

The final helper must use the existing parameterized countdown body. The forwarding helper must be exactly:

```do
async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
    return await(pending)
}
```

The root must call `forward_stream(writer, count, value)` and await it; the
check fixture ends with `start() {}`.

- [x] **Step 2: Add red async-plan assertions.**

Assert `producer_mode == .countdown`, `producer_helper_name == "forward_stream"`,
`producer_count_name == "count"`, and `producer_value_name == "value"`. Add
source variants that reorder `(count, writer, value)` and add
`forward_stream -> middle_stream -> finish_stream`; both must return
`error.UnsupportedP3StreamWriterComponent`.

- [x] **Step 3: Add the red emitter assertion.**

Compile the fixture through `emit_wat` and assert the guest-producer marker,
async-helper marker, offsets `52`/`60`, `$async-run-i64-i32`, the single root
export, and absence of `[async-lift]forward_stream`.

- [x] **Step 4: Run the red tests.**

```bash
cd src && zig test build/codegen_component_async_plan.zig --test-filter 'parameterized producer forwarding'
cd src && zig test build/codegen_component_stream_writer.zig --test-filter 'parameterized forwarding'
```

Expected: the new positive tests fail because only the direct parameterized
helper is currently recognized.

### Task 2: Implement strict one-hop parameterized forwarding analysis

**Files:**
- Modify: `src/build/codegen_component_async_plan.zig`

**Interfaces:**
- Consumes the root transfer binding and exact parameterized helper metadata.
- Produces the same `GuestProducerFunction` countdown facts as the direct helper path.

- [x] **Step 1: Add a parameterized forwarding-helper descriptor matcher.**

Reuse the existing exact signature matcher, but parse the body as one
`Future<Result<nil, E>> = finish(writer, count, value)` binding followed by
`return await(binding)`. Require the callee's three arguments to be the
forwarder's direct parameter names and reject any extra token.

- [x] **Step 2: Resolve exactly one final helper.**

From the forwarding body resolve the named final helper with the exact
`(StreamWriter<u8>, u64, u8)` signature. Pass its body through the existing
`parse_dynamic_guest_producer_body` using its parameter names and require the
same Result token range as the forwarding and root functions.

- [x] **Step 3: Wire the root path and preserve rejection boundaries.**

When the root's direct dynamic path does not match, accept one forwarding
binding, return the root metadata with `helper_name == "forward_stream"`, and
reject a second forwarding hop, literal/crossed arguments, missing await, or
forwarder-side writer operations. Leave fixed-sequence and direct parameterized
paths unchanged.

- [x] **Step 4: Run focused parser/emitter tests.**

```bash
cd src && zig test build/codegen_component_async_plan.zig --test-filter 'parameterized producer forwarding'
cd src && zig test build/codegen_component_stream_writer.zig --test-filter 'parameterized forwarding'
```

### Task 3: Component and Rust/Wasmtime gates

**Files:**
- Create: `examples/p3-runtime/wit/stream-probe-guest-producer-parameterized-forwarding-helper.wit`
- Create: `examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_forwarding_helper.sh`
- Create: `examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_forwarding_helper.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs` only if a distinct mode is required.

**Interfaces:**
- Consumes the Task 1 source fixture and the existing `parameterized-helper` runtime mode.
- Produces Component validation and pending/ready/error Wasmtime evidence for the new chain.

- [x] **Step 1: Add the WIT sidecar.**

Copy the parameterized helper sidecar exactly; the world and export remain
`stream-writer-probe` and `produce: async func(count: u64, value: u8)`.

- [x] **Step 2: Add the Component lowering script.**

Build the fixture with `--p3-async-component --p3-wit-output`, compare the
sidecar, require the helper marker and frame offsets, assert only the root
export, then run `wasm-tools parse`, `component embed`, `component new`, and
`wasm-tools validate --features cm-async,cm-more-async-builtins`.

- [x] **Step 3: Add the Rust/Wasmtime script.**

Assemble the Component and invoke the existing runner with
`parameterized-helper` in pending, ready, and error modes. Require
`count=0/1/3`, `value=90`, ordered bytes, one callback, and one stream drop.

### Task 4: Documentation and full verification

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/async-design.md`
- Modify: `doc/spec_rules.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [x] **Step 1: Record the bounded checkpoint.**

Document the exact one-hop parameterized chain and its rejection boundaries;
do not close general producer/resource blockers.

- [x] **Step 2: Run focused and repository gates.**

```bash
cd src && zig test build/codegen_component_async_plan.zig --test-filter 'parameterized producer forwarding'
cd src && zig test build/codegen_component_stream_writer.zig --test-filter 'parameterized forwarding'
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_forwarding_helper.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_forwarding_helper.sh
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
bash src/build/test/run_release_smoke.sh
zig fmt --check src/build/codegen_component_async_plan.zig src/build/codegen_component_stream_writer.zig
rustfmt --check --edition 2024 examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs
bash -n examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_forwarding_helper.sh examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_forwarding_helper.sh
git diff --check
```

- [x] **Step 3: Mark this plan complete only from green evidence.**

Keep the general async call, arbitrary producer expression, third-hop, and
borrowed/nested/variant resource boundaries explicitly pending.
