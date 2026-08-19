# G5a `[u8]` `@put` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add one parsed Wasm-GC lowering for `@put(input, value) -> [u8]` while preserving immutable source-value semantics.

**Architecture:** Extend the existing test-only synchronous GC emitter with a narrow byte-list `@put` expression matcher. Allocate a result array at runtime length plus one, copy the source payload, and set the appended element; keep normal `do build` on ARC until G5b/G5c.

**Tech Stack:** Zig 0.16, parsed Do tokens/AST model, WAT Core GC, wasm-tools 1.255.0, Wasmtime GC execution probes.

**Spec:** `doc/superpowers/specs/2026-08-13-gc-byte-list-put-design.md`

## Global Constraints

- Do source remains pointer-free and reference-free; no public ownership or reference syntax is added.
- One emitted module uses one managed-value representation; never mix ARC handles and GC references.
- The normal `do build` backend remains ARC during G5a.
- `@put` admission is limited to one `[u8]` receiver and one `u8` value.
- Every rejected neighboring shape fails closed before WAT.

---

### Task 1: Add the failing parsed-emitter matrix

**Files:**
- Modify: `src/build/codegen_pipeline.zig` near the existing parsed byte-list GC tests
- Test: existing Zig unit suite in `src/build/codegen_pipeline.zig`

**Interfaces:**
- Consumes: `emit_gc_wat_for_source` and `error.UnsupportedGcSync*` errors.
- Produces: failing tests for one-value append and its rejection neighbors.

- [x] **Step 1: Write the failing tests**

Add tests for:

```do
append_byte(input [u8], value u8) -> [u8] {
    return @put(input, value)
}
start() {}
```

Assert the WAT contains `array.new_default $do_bytes`, `array.copy $do_bytes $do_bytes`, `array.set $do_bytes`, and no `__arc_`. Add separate tests asserting `@put(input, 1, 2)`, `@put(input, ...values)`, and a `[u32]` receiver fail with `UnsupportedGcSyncExpression` or `UnsupportedGcSyncType` as defined by the spec.

- [x] **Step 2: Run the focused test to verify RED**

Run: `cd src && zig test build/codegen_pipeline.zig`

Expected: the new single-value append test fails with `UnsupportedGcSyncExpression`; the existing suite remains otherwise runnable.

### Task 2: Implement the minimal GC lowering

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Test: `src/build/codegen_pipeline.zig`

**Interfaces:**
- Consumes: parsed `@put` call tokens, the existing `[u8]` local lookup, `GcListTemps`, and scalar expression emission.
- Produces: a `[u8]` GC reference with a copied source payload and one appended element.

- [x] **Step 1: Add a narrow `@put` matcher**

Recognize only `@put(receiver, value)` with an identifier receiver of type `[u8]`. Reject spread and any additional comma-separated value before emitting instructions. Validate the expected result as `[u8]` and emit the value with expected type `u8`.

- [x] **Step 2: Emit runtime-length copy plus append**

Use the existing temporary locals. Compute `length + 1`, allocate `array.new_default $do_bytes`, copy `length` elements with `array.copy`, then write at index `length` with `array.set`. Return the new list reference and leave the source untouched.

- [x] **Step 3: Run the focused Zig suite**

Run: `cd src && zig test build/codegen_pipeline.zig && zig test build/codegen_gc_sync.zig`

Expected: all focused tests pass and generated GC WAT has no ARC runtime symbol.

### Task 3: Add and run the executable GC probe

**Files:**
- Modify: `src/build/gc_sync_probe.zig`
- Modify: `examples/gc-p3-runtime/test_do_gc_list_put.sh`
- Create: `examples/gc-p3-runtime/list-put.do`
- Modify: `examples/gc-p3-runtime/README.md`

**Interfaces:**
- Consumes: the parsed GC emitter and probe wrapper.
- Produces: a Wasm-tools/Wasmtime gate for empty and non-empty append behavior.

- [x] **Step 1: Add the fixture and probe shape**

Use a zero-parameter `make() -> [u8]` fixture plus `append_byte(input [u8], value u8) -> [u8]`, or a dedicated probe fixture whose exported `probe` calls the admitted append function with an empty and a three-byte source. Keep the source list rooted while checking old bytes and result bytes.

- [x] **Step 2: Run the probe**

Run: `WASM_TOOLS_BIN="$(command -v wasm-tools)" WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_list_put.sh`

Expected: WAT parses, Wasmtime compiles with `-W gc=y`, and `probe` returns `27815` after validating old-value preservation, appended bytes, and distinct result allocation.

### Task 4: Run regression and synchronize status

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `examples/gc-p3-runtime/README.md`

**Interfaces:**
- Consumes: focused and full verification output.
- Produces: a dated, evidence-backed G5a `@put` checkpoint and explicit G5b/G5c boundary.

- [x] **Step 1: Run the required verification**

Run:

```bash
cd src && zig test main.zig
./src/build/test/run_tests.sh
RUN_GC_CORE=1 ./src/build/test/run_tests.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" WASMTIME_BIN="$(command -v wasmtime)" bash src/build/test/check_gc_core_oracles.sh
```

Expected: no new failures; preserve exact counts from the current run.

- [x] **Step 2: Record status and residual risks**

Record the exact focused/probe/full outputs, the accepted `@put` shape, and the rejection neighbors. State that normal `do build` is still ARC and G5b equivalence/G5c cutover remain pending.

### Task 5: Final verification and handoff

**Files:**
- Inspect: all changed files and `git diff --check`

- [x] **Step 1: Verify the final diff**

Run: `git diff --check` and `git status --short`

Expected: only the scoped implementation, tests, probe, and status documentation are changed; no default backend switch or public ownership/reference syntax appears.
