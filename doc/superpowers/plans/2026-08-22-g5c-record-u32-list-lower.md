# G5c Bounded Record `list<u32>` Lower Implementation Plan

> Execute this plan inline in the current checkout. Preserve unrelated dirty
> worktree changes. Do not reset, checkout, clean, commit, or push as part of
> this plan unless separately authorized.

**Spec:** `doc/superpowers/specs/2026-08-22-g5c-record-u32-list-lower-design.md`

## Scope and fixed contract

The only newly admitted descriptor is
`demo:marshal-record-u32-list-lower/api.write@1.0.0/lower`:

```text
Writing { code: u32, payload: [u32] }
record layout: 12 bytes, alignment 4
canonical import: (i32, i32, i32)
payload lengths: 0..3
```

The lowerer copies the GC `u32` array to temporary linear memory, calls the
canonical import, and frees that allocation exactly once. Every other
record/list shape remains rejected by this GC route and keeps the existing ARC
fallback.

## Files and responsibilities

| Area | Files | Responsibility |
| --- | --- | --- |
| Descriptor inputs | `examples/gc-p3-runtime/marshal-record-u32-list-lower-manifest-source.wit`, `doc/wit/gc_marshal_record_u32_list_lower_imports.wit`, `examples/gc-p3-runtime/marshal-record-u32-list-lower-assembly.wit`, `examples/gc-p3-runtime/ordinary-host-record-u32-list-lower-call.do` | Pin WIT source, imports, Component world, and exact Do host boundary. |
| Manifest and route | `doc/wit/gc_descriptor_manifest.json`, `src/build/codegen_gc_wit_host_boundary.zig`, `src/build/codegen_gc_wit_marshal.zig`, `src/build/run.zig`, `src/build/codegen_component_manifest_route_test.zig` | Hash-checked descriptor, source admission, explicit adapter, and ordinary default admission. |
| Typed planning | `src/build/codegen_component_marshal_ops.zig`, `src/build/codegen_component_descriptor_manifest.zig`, `src/build/codegen_gc_plans_test.zig` | Materialize the measured `list<u32>` child and expose only the fixed root plan. |
| WAT emission | `src/build/codegen_component_marshal_wat.zig`, `src/build/gc_marshal_record_u32_list_lower_probe.zig`, `src/main.zig` | Emit temporary allocation/copy/call/free and the standalone probe wrapper. |
| Runtime evidence | `examples/gc-p3-runtime/marshal-record-u32-list-lower-arc.core.wat`, `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_u32_list_lower.rs`, `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_u32_list_lower_equivalence.rs`, the three u32-list gate scripts | Provide the fixed linear oracle and Rust/Wasmtime observations. |
| Gate/docs | `src/build/test/check_gc_default_build_gate.sh`, `src/build/test/check_gc_g5c_residual_gate.sh`, `src/build/test/check_gc_g5c_residual_gate_test.sh`, `src/build/test/check_gc_migration_inventory.sh`, `src/build/test/run_release_smoke.sh`, `CHANGELOG.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/host_abi_blockers.md` | Lock fixture count, gate coverage, migration inventory, and current status. |

## Tasks

1. **Pin inputs and red boundaries.** Add the package/interface/world mirrors,
   the synchronous Do fixture, manifest entry with source hash
   `sha256:30a6d8c42680333d2c0b359888f589d41d30a82fc105e94ef1a43e0920fc519b`,
   and six compile-error fixtures for async, locator, member, order, element,
   and extra-field drift.
2. **Materialize the fixed typed plan.** Convert the manifest list facts into
   one `i32` scalar child with element size/stride/alignment `4`; require the
   12-byte root, capacity `3`, lengths `0..3`, and `cabi_realloc` actions. Keep
   arbitrary list elements and nested/multiple list fields fail-closed.
3. **Emit the lower and wire source admission.** Load the root by numeric field
   index, guard `4 * len`, copy `$do_u32` elements with `i32.store`, call the
   `(i32,i32,i32)` import, then free the temporary span. Admit only the exact
   synchronous Do/WIT boundary; leave unadmitted shapes on ARC fallback.
4. **Close runtime gates.** Run the manifest host gate, ARC/GC equivalence gate,
   and six-case negative gate. Each gate must use `wasm-tools 1.255.0`, reject
   GC references crossing the canonical import, and preserve exactly-once
   allocation/free behavior.
5. **Promote the exact default fixture.** Add
   `ordinary-host-record-u32-list-lower-call.do` to the 73-fixture manifest and
   assert its import, `array.get $do_u32`, `i32.store`, call/free ordering, GC
   marker, and absence of ARC markers. Keep the 15-row inventory pending.
6. **Synchronize and verify.** Update the changelog, start-here, pending,
   blockers, roadmap, and runtime README. Then run the focused Zig/gate tests,
   full regression, ReleaseSmall, release smoke, and `git diff --check`.

## Verification record

The implementation is verified with focused `u32-list` plan tests, host,
equivalence, and negative gates; the full regression reports `pass=1306
fail=0 skip=3`, ReleaseSmall and release smoke pass, and the default GC gate
covers 73 fixtures. The migration inventory intentionally remains
`complete_rows=15 pending_rows=15` with exit 1.

## Non-goals and rollback

Do not widen this plan to general `list<T>`, list lift, async/resource
lowering, or ownership syntax. If a gate fails, remove only this descriptor,
its fixtures, route entry, and dedicated tests; retain the prior admitted
descriptors and ARC fallback unchanged.
