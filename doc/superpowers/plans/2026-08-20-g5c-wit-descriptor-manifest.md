# G5c WIT Descriptor Manifest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace caller-supplied WIT source and descriptor facts with a checked-in, hash-verified manifest for bounded GC host/WIT marshal plans.

**Architecture:** Add a small `src/wit/descriptor_manifest.zig` parser/validator that owns no compiler state. A build-side loader reads repository-relative WIT sources, verifies the manifest hash, resolves one member through the existing WIT resolver, and produces the existing parser-backed marshal request. The A random gate is migrated first; default host/WIT routing and G5c cutover remain unchanged.

**Tech Stack:** Zig 0.16, existing `src/wit` parser/resolver, `std.json`, existing measured marshal plan, pinned `wasm-tools 1.255.0`, Rust/Wasmtime runner.

**Spec:** `doc/superpowers/specs/2026-08-20-g5c-wit-descriptor-manifest.md`

## Global Constraints

- Default `do build` host/WIT routing remains ARC-backed.
- Manifest source paths are repository-relative and reject absolute paths and `..` traversal.
- Hashes are lowercase `sha256:` plus exactly 64 hex digits.
- Unsupported WIT shapes fail closed before WAT emission.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, or new async syntax.
- Preserve the legacy `cm32p2|wasi:*` host-core route; Component marshal uses versioned WIT identity.

### Task 1: Parse and validate descriptor manifest records

**Files:**
- Create: `src/wit/descriptor_manifest.zig`
- Modify: `src/main.zig`
- Test: `src/wit/descriptor_manifest_test.zig`

**Interfaces:**
- Produces: `Manifest`, `Descriptor`, `parse`, `find_descriptor`.
- Errors: malformed schema, path traversal, duplicate id, invalid hash, and unknown id.

- [x] **Step 1: Write the failing tests** for one valid descriptor plus malformed JSON, duplicate id, absolute/parent paths, invalid hash, and unknown id.
- [x] **Step 2: Run `cd src && zig test wit/descriptor_manifest_test.zig` and observe the expected missing-module failure.**
- [x] **Step 3: Implement the minimal JSON parser and structural guards.** Do not read files or resolve WIT in this module.
- [x] **Step 4: Re-run the focused tests and verify all parser cases pass.**

### Task 2: Resolve source files and verify provenance

**Files:**
- Create: `src/build/codegen_component_descriptor_manifest.zig`
- Modify: `src/build/codegen_component_marshal_route.zig`
- Test: `src/build/codegen_gc_plans_test.zig`

**Interfaces:**
- Consumes: `descriptor_manifest.Descriptor`, repository root, and measured layout.
- Produces: an owned `marshal_route.Request` with source bytes and resolved descriptor identity.

- [x] **Step 1: Add RED tests** for valid random descriptor, source hash drift, package/version drift, member/signature drift, and unsupported shape.
- [x] **Step 2: Run `cd src && zig test main.zig --test-filter 'descriptor manifest'` and preserve the failure.**
- [x] **Step 3: Implement guarded path resolution, exact source concatenation, SHA-256 verification, WIT resolution, and manifest-vs-parser comparisons.**
- [x] **Step 4: Re-run focused tests and confirm no independent caller descriptor can bypass the loader.**

### Task 3: Migrate the A gate to the manifest

**Files:**
- Create: `doc/wit/gc_descriptor_manifest.json`
- Modify: `src/build/gc_wasi_random_probe.zig`
- Modify: `examples/gc-p3-runtime/test_gc_wasi_random_list_lift.sh`
- Test: `examples/gc-p3-runtime/test_gc_wasi_random_list_lift.sh`

- [x] **Step 1: Add a RED assertion** that the A probe loads by descriptor id and rejects a mutated source file.
- [x] **Step 2: Run the A gate and observe the missing manifest route.**
- [x] **Step 3: Switch the probe to the manifest loader and add the checked-in random descriptor with its computed source hash.**
- [x] **Step 4: Run the A gate end-to-end:** parser, manifest hash, `wasm-tools parse/embed/new/validate`, and Rust/Wasmtime host execution.

### Task 4: Add drift and residual documentation gates

**Files:**
- Modify: `src/build/test/check_gc_g5c_residual_gate.sh`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`

- [x] **Step 1: Add a negative manifest drift check** that exits non-zero without changing the default ARC residual assertions.
- [x] **Step 2: Run the residual baseline gate, inventory gate, full Zig test root, and A shell gate.**
- [x] **Step 3: Record exact outputs, keep `host_wit_marshalling` G5c pending, and document B completion criteria.**

## Completion Criteria

1. A valid descriptor is resolved only from the manifest and exact WIT source bytes.
2. Hash, path, package/version, world/member, signature, and canonical import drift fail before WAT emission.
3. The A gate passes unchanged after migration to the manifest.
4. The default host/WIT route remains ARC-backed and no async/resource shape is admitted.
