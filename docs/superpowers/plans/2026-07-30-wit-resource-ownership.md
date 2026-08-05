# WIT Resource Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a descriptor-bound Component resource probe with affine Do resource ownership, canonical `own`/`borrow` lowering, and a Wasmtime `ResourceTable` execution test.

**Architecture:** Do source keeps nominal `@wasi_resource` names. A registry owns the WIT resource identity and ownership qualifiers; sema consumes or preserves bindings from those qualifiers. A dedicated probe emitter writes Core WAT and assembly WIT. This slice excludes HTTP and generic async lowering.

**Tech Stack:** Zig compiler, WAT, wasm-tools 1.254.0, Rust 1.97.0, Wasmtime 47.0.2 Component Model ResourceTable.

## Global Constraints

- Do gains no public `own<T>` / `borrow<T>`, pointer/reference, `externref`, `anyref`, `funcref`, or `i31ref` syntax.
- Only a pinned registry may declare resource ownership. Never infer it from a member name or resource spelling.
- `@wasi_resource` is opaque to source. The handle may appear only inside ABI lowering.
- `own` consumes a binding; `borrow` is call-scoped and preserves it; there is no implicit drop.
- The private test package is `do:resource-probe@0.1.0`. It must not be described as HTTP, generic WASI, or generic async support.
- Worktree is shared and dirty: do not reset, clean, stage, or commit unrelated changes.

---

### Task 1: Resource Descriptor Registry And WIT Fixture

**Files:**

- Create: `src/build/resource_abi_registry.zig`
- Create: `src/build/resource_abi_registry.json`
- Create: `examples/p3-runtime/wit/resource-probe.wit`
- Create: `examples/p3-runtime/verify_resource_probe_wit.sh`
- Test: Zig unit tests in `src/build/resource_abi_registry.zig`

**Interfaces:**

- Produces `Registry.load`, `Registry.find(locator, member)`, `Descriptor`, `Param{ type_name, ownership }`, and `Ownership = enum { none, own, borrow }`.
- The registry contains only `do:resource-probe/ledger@0.1.0`: `create(u32) -> own<ticket>`, `borrow-value(borrow<ticket>) -> u32`, `consume(own<ticket>) -> u32`, and resource-drop `ticket`.

- [x] **Step 1: Write the failing registry tests**

```zig
test "resource descriptor preserves ownership qualifiers" {
    var registry = try Registry.load(std.testing.allocator, fixture_json);
    defer registry.deinit(std.testing.allocator);
    try std.testing.expectEqual(.borrow, registry.find(locator, "borrow-value").?.params[0].ownership);
    try std.testing.expectEqual(.own, registry.find(locator, "consume").?.params[0].ownership);
}
```

- [x] **Step 2: Verify red state**

Run: `cd src && zig test build/resource_abi_registry.zig`

Expected: fail because the module does not exist.

- [x] **Step 3: Implement strict registry decoding and WIT**

Reject duplicate descriptors, unknown ownership strings, missing resource identity, non-resource `own`/`borrow`, and a drop descriptor that does not receive one owning resource. The WIT uses a `ticket` resource, free functions `create`, `borrow-value`, and `consume`, and the resource destructor rather than a fake `drop: func`.

- [x] **Step 4: Verify green state**

Run:

```bash
cd src && zig test build/resource_abi_registry.zig
cd .. && bash examples/p3-runtime/verify_resource_probe_wit.sh
```

Expected: registry tests pass and wasm-tools accepts the probe world.

### Task 2: Affine Resource Semantic Pass

**Files:**

- Create: `src/build/sema_resource_ownership.zig`
- Modify: `src/build/sema.zig`
- Modify: `src/build/diag.zig`
- Modify: `src/build/sema_imports.zig`
- Create: `src/build/test/check/356_resource_borrow_preserves_owner.do`
- Create: `src/build/test/err/364_resource_after_own.do`
- Create: `src/build/test/err/364_resource_after_own.expect`
- Create: `src/build/test/err/365_resource_drop_twice.do`
- Create: `src/build/test/err/365_resource_drop_twice.expect`
- Create: `src/build/test/err/366_resource_leaked.do`
- Create: `src/build/test/err/366_resource_leaked.expect`

**Interfaces:**

- Produces `check_resource_ownership(allocator, tokens) !void`.
- Reports `ResourceAlreadyConsumed` after own transfer or a second drop, and `ResourceDropped` at scope exit with an active resource.

- [x] **Step 1: Add red source fixtures**

```do
ticket Ticket = create(7)
consume(ticket)
borrow_value(ticket)
```

This must report `ResourceAlreadyConsumed`. A second `drop(ticket)` must report the same diagnostic. A live `Ticket` at the end of `start` must report `ResourceDropped`. The check fixture calls `borrow_value(ticket)` twice and then transfers the ticket once.

- [x] **Step 2: Verify red state**

Run: `./bin/do check src/build/test/err/364_resource_after_own.do`

Expected: it incorrectly passes before the pass is installed.

- [x] **Step 3: Implement descriptor-bound tracking**

Collect only locals whose type is an `@wasi_resource` declared in the current module. On a known resource host call, type-check each qualified argument, consume it for `own`, retain it for `borrow`, and activate the target binding for an owning result. A same-type local initialization transfers ownership. Do not track ordinary structs or unknown host calls.

- [x] **Step 4: Verify green state**

Run:

```bash
cd src && zig test build/sema_resource_ownership.zig
cd .. && ./bin/do check src/build/test/check/356_resource_borrow_preserves_owner.do
./bin/do check src/build/test/err/364_resource_after_own.do
./bin/do check src/build/test/err/365_resource_drop_twice.do
./bin/do check src/build/test/err/366_resource_leaked.do
```

Expected: the check fixture passes; every error fixture reports its expected diagnostic before WAT lowering.

### Task 3: Component Resource Probe Lowering

**Files:**

- Create: `src/build/codegen_component_resource_probe.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/codegen_api.zig`
- Modify: `src/build/cli.zig`
- Modify: `src/main.zig`
- Create: `examples/p3-runtime/resource-probe.do`
- Test: Zig unit tests in `src/build/codegen_component_resource_probe.zig`

**Interfaces:**

- Produces `do build resource-probe.do --p3-resource-probe-component --p3-wit-output probe.wit -o probe.wat`.
- The opt-in emitter accepts only the registered probe data flow and emits Core WAT and WIT sidecar from the same descriptor data. Ordinary `do build` behavior stays unchanged.

- [x] **Step 1: Add red emitter and CLI tests**

```zig
test "resource probe emits canonical own borrow and drop imports" {
    const wat = try emit_component_wat(std.testing.allocator, probe_tokens);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]ticket") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "borrow-value") != null);
}
```

Add CLI tests rejecting this target combined with `--p3-wait-for-component`, `--component-core`, or `--host-export`, and rejecting `--p3-wit-output` when neither P3 target is selected.

- [x] **Step 2: Verify red state**

Run: `cd src && zig test build/codegen_component_resource_probe.zig`

Expected: fail because the emitter and target do not exist.

- [x] **Step 3: Implement descriptor-driven Core emission**

Load the resource registry and parse only registered declarations and the probe `run` flow. Emit the exact Core imports, resource handle conversions, canonical resource operations, and one explicit `[resource-drop]ticket` call. Emit matching WIT sidecar. Do not reuse filesystem/socket resource emitters and do not lower unrelated source into a component.

- [x] **Step 4: Verify component assembly**

Run: `bash examples/p3-runtime/test_do_resource_probe_lowering.sh`

Expected: do emits Core WAT, wasm-tools embeds and assembles it, and a changed source shape is rejected.

### Task 4: Wasmtime ResourceTable Adapter

**Files:**

- Create: `examples/p3-runtime/rust-host-runner/src/resource_probe.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_rust_resource_probe.sh`
- Create: `examples/p3-runtime/test_do_resource_probe_lowering.sh`

**Interfaces:**

- Produces `do-p3-resource-probe-host-runner <component.wasm>`.
- Host state owns `ResourceTable`, inserts tickets on create, reads without deletion on borrow, deletes on consume, and counts canonical resource drops.

- [x] **Step 1: Add the red runtime assertion**

The script requires these markers:

```text
Rust P3 resource adapter passed
ticket create=2
ticket borrow=2
ticket consume=1
ticket drop=1
```

- [x] **Step 2: Verify red state**

Run: `bash examples/p3-runtime/test_do_resource_probe_lowering.sh`

Expected: fail because the runner and compiler target do not exist.

- [x] **Step 3: Implement typed host resources**

Use Wasmtime Component bindings and `ResourceTable`, never an integer map. Borrow uses `ResourceTable.get`; consume uses `ResourceTable.delete`; the destructor increments its count only for a still-owned table entry. Run Cargo as `cargo run --bin do-p3-resource-probe-host-runner --` so the added binary cannot break the wait-for runner.

- [x] **Step 4: Verify green runtime behavior**

Run: `bash examples/p3-runtime/test_do_resource_probe_lowering.sh`

Expected: the assembled component emits all four markers and returns zero.

### Task 5: Documentation And Regression Closeout

**Files:**

- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/spec_rules.md`
- Modify: `examples/p3-runtime/README.md`
- Modify: `src/build/test/run_tests.sh`

**Interfaces:**

- Documents only the verified private resource probe. HTTP `client.send`, WIT future/stream, generic async, resource arrays, and Component-GC remain blocked.

- [x] **Step 1: Add the semantic fixtures to the standard test entrypoint**

Keep the Rust adapter under `examples/p3-runtime/test.sh`; do not turn it into an unconditional compiler-suite dependency.

- [x] **Step 2: Synchronize support boundaries**

State that `@wasi_resource` is opaque, WIT ownership is compiler-enforced, and no public `own<T>` / `borrow<T>` syntax exists. State the package/version and exclusions exactly.

- [x] **Step 3: Run the verification matrix**

Run:

```bash
cd src && zig build -Doptimize=ReleaseSmall
cd .. && ./src/build/test/run_tests.sh
./examples/p3-runtime/test_do_resource_probe_lowering.sh
./examples/p3-runtime/test.sh
git diff --check
```

Expected: all compiler and resource-probe tests pass; documentation makes no HTTP, generic resource ABI, or generic async completion claim.
