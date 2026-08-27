# G5c Bounded Record `list<u8>` Lower Implementation Plan

> Execute this plan inline in the current checkout. Preserve all unrelated
> dirty-worktree changes. Do not reset, checkout, clean, commit, or push as
> part of this plan unless separately authorized.

**Spec:** `doc/superpowers/specs/2026-08-22-g5c-record-byte-list-lower-design.md`

## Scope and fixed contract

The only newly admitted descriptor is
`demo:marshal-record-byte-list-lower/api.write@1.0.0/lower`:

```text
Writing { code: u32, payload: [u8] }
record layout: 12 bytes, alignment 4
canonical import: (i32, i32, i32)
payload lengths: 0..4
```

The generated lowerer copies the GC byte array to temporary linear memory,
calls the canonical import, and frees that allocation exactly once. Every
other record/list shape remains rejected by the GC route and continues through
the existing ARC fallback.

## Files and responsibilities

| Area | Files | Responsibility |
| --- | --- | --- |
| Descriptor inputs | `examples/gc-p3-runtime/marshal-record-byte-list-lower-manifest-source.wit`, `doc/wit/gc_marshal_record_byte_list_lower_imports.wit`, `examples/gc-p3-runtime/marshal-record-byte-list-lower-assembly.wit`, `examples/gc-p3-runtime/ordinary-host-record-byte-list-lower-call.do` | Pin WIT source, imports, Component world, and exact Do host boundary. |
| Manifest and route | `doc/wit/gc_descriptor_manifest.json`, `src/build/codegen_gc_wit_host_boundary.zig`, `src/build/codegen_gc_wit_marshal.zig`, `src/build/run.zig`, `src/build/codegen_component_manifest_route_test.zig` | Hash-checked descriptor, source admission, explicit adapter, and ordinary default admission. |
| Typed planning | `src/build/codegen_component_marshal_ops.zig`, `src/build/codegen_gc_plans_test.zig` | Recognize only the root `u32 + list<u8>` field shape and expose its ordered operations. |
| WAT emission | `src/build/codegen_component_marshal_wat.zig`, `src/build/gc_marshal_record_byte_list_lower_probe.zig`, `src/main.zig` | Emit temporary allocation/copy/call/free and a standalone probe wrapper. |
| Runtime evidence | `examples/gc-p3-runtime/marshal-record-byte-list-lower-arc.core.wat`, `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_byte_list_lower.rs`, `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_byte_list_lower_equivalence.rs`, positive/negative/equivalence shell gates | Provide fixed linear oracle and Rust/Wasmtime observations. |
| Gate/docs | `src/build/test/check_gc_default_build_gate.sh`, `src/build/test/check_gc_g5c_residual_gate.sh`, `src/build/test/check_gc_g5c_residual_gate_test.sh`, `src/build/test/check_gc_migration_inventory.sh`, `src/build/test/run_release_smoke.sh`, `CHANGELOG.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/host_abi_blockers.md` | Lock fixture count, gate coverage, migration inventory, and current status. |

## Task 1: Add pinned inputs and red boundaries

1. Add the WIT source with one `writing` record and `write` function, plus the
   matching imports and `probe` world. Keep package/interface/member names
   identical to the descriptor id.
2. Add the Do fixture with exactly one synchronous declaration:

   ```do
   write = @host_func("demo:marshal-record-byte-list-lower/api@1.0.0", "write", (Writing) -> nil)

   Writing {
       code u32
       payload [u8]
   }
   ```

   Construct `Writing{code = 7, payload = [10, 20, 5]}` and call `write` from
   `start`.
3. Add compile-error fixtures for async declaration, locator mismatch, member
   mismatch, field reorder, `[u16]` payload, and an extra record field. Each
   `.expect` file must match the existing fail-closed diagnostic class.
4. Add the manifest entry with the source hash, WIT-derived canonical import,
   measured root record, measured byte-list child, `cabi_realloc` actions,
   capacity `4`, and accepted lengths `[0,1,2,3,4]`.
5. Before route admission, add unit tests that require the new manifest entry
   to decode and that require the host boundary to reject each red fixture.
   These tests are expected to fail until Tasks 2 and 3 add the descriptor
   recognition; do not weaken the expected errors to make them pass.

## Task 2: Extend the typed memory plan with one managed byte-list field

1. Add a `ManagedByteListField` record to
   `codegen_component_marshal_ops.zig` containing the field index, measured
   pointer/length offsets, and element stride. Add corresponding fields to
   `MemoryPlan` without changing the existing managed-text fields.
2. Implement `managed_byte_list_field_for_root` with these guards:
   - root is a non-indirect record with exactly two children;
   - child 0 is scalar `u32` with core type `i32`;
   - child 1 is a byte list with byte size `8`, alignment `4`, pointer offset
     `0`, length offset `4`, element stride `1`, and `cabi_realloc` allocation/free;
   - the child element is scalar `u8` and no nested child/resource metadata is
     present.
3. Select a separate operation list for this shape. Its order is
   `read_gc_span`, `validate_linear_range`, `cabi_realloc_alloc`,
   `copy_to_linear`, `canonical_call`, `cabi_realloc_free`.
4. Keep `validate_record_lower_node` fail-closed for all other list children,
   nested list children, multiple managed fields, and indirect roots.
5. Add `codegen_gc_plans_test.zig` cases for the positive 12-byte plan, empty
   and maximum accepted lengths, wrong stride, wrong element type, and a list
   field in a non-root/nested record. Verify the positive plan never marks a
   GC reference as crossing the canonical boundary.

## Task 3: Emit the canonical lower and explicit probe

1. Add `emit_record_lower_managed_byte_list` in
   `codegen_component_marshal_wat.zig`. It must:
   - load `payload` from the compiler root by numeric field index;
   - compute `array.len`, guard the maximum span, and allocate `len` bytes;
   - loop over `$do_bytes` with `array.get_s` and `i32.store8`;
   - load `code`, pointer, and length in canonical order;
   - call the canonical import;
   - call `cabi_realloc(ptr, len, 1, 0)` exactly once after the call;
   - leave no GC reference in the import signature.
2. Route `record_managed_byte_list_lower` before the generic flat-record path;
   do not reuse the text emitter in a way that reads `$do_text` or its length
   field.
3. Add emitter unit tests asserting the `(i32 i32 i32)` canonical type, one
   byte-copy loop, `array.get_s $do_bytes`, numeric root field access, and one
   post-call free. Assert that an unsupported list record returns
   `UnsupportedMarshalShape`.
4. Add a standalone Zig probe module and `src/main.zig` import. Its fixed GC
   wrapper constructs bytes `[10,20,5]`, invokes `$marshal`, and returns the
   callback result plus allocation/free counters for the host gate.

## Task 4: Wire source admission, manifest route, and runtime gates

1. Add the descriptor constant and exact `HostBoundarySpec` with fields
   `code: u32` and `payload: [u8]` to `codegen_gc_wit_host_boundary.zig`. Extend
   only the WIT-to-Do type matcher needed for `list<u8>`; `[u16]`, `text`, and
   nested records must remain mismatches for this descriptor.
2. Add the descriptor to `codegen_gc_wit_marshal.zig` and the ordinary
   `admitted_gc_host_descriptor` map in `run.zig`. Add focused route tests for
   explicit and default dispatch; unknown and unadmitted descriptors must stay
   rejected or ARC-backed.
3. Add a hand-authored ARC Core oracle with the same canonical import and WIT.
   Add Rust runners that verify exact bytes, `code=7`, one host callback,
   `result=42`, and one allocation/free for each path; the equivalence runner
   must compare GC and ARC results, bytes, and callback counts.
4. Add three shell gates:
   - host: build ordinary Do, assert `;; gc-sync`, no `__arc_`, canonical
     `(i32,i32,i32)`, no `(ref` on the import, assemble/validate, run host;
   - equivalence: assemble generated GC and ARC oracle from the same WIT and
     compare runner observations;
   - negative: run all red fixtures, assert failure before WAT and no output
     file, and assert an unadmitted host fixture still contains ARC markers.
5. Add the host/equivalence/negative scripts to the residual gate and its
   static wiring test. Add the fixture and exact WAT checks to the 70-fixture
   default build gate. Add all source/WIT/oracle/runner/gate paths to the
   migration inventory without changing its intentional `15/15` status.

## Task 5: Verification and documentation

Run in this order, preserving failures as evidence:

```bash
bash -n examples/gc-p3-runtime/test_gc_default_host_route_byte_list_lower*.sh \
  src/build/test/check_gc_g5c_residual_gate.sh \
  src/build/test/check_gc_g5c_residual_gate_test.sh \
  src/build/test/check_gc_default_build_gate.sh \
  src/build/test/check_gc_migration_inventory.sh
git diff --check
bash src/build/test/check_gc_g5c_residual_gate_test.sh
bash src/build/test/check_gc_g5c_residual_gate.sh baseline
./src/build/test/run_tests.sh
(cd src && zig test main.zig)
(cd src && zig build -Doptimize=ReleaseSmall)
./src/build/test/run_release_smoke.sh
```

Record actual counts, tool versions, host observations, and the deliberate
inventory exit status. Update `CHANGELOG.md`, `doc/start_here.md`,
`doc/roadmap_status.md`, `doc/pending_blocked.md`, and
`doc/host_abi_blockers.md` to say that only this fixed byte-list record lower
is closed. Keep general list-record lower, arbitrary aggregates,
async/resource lowering, ownership syntax, and full G5c cutover pending.

## Self-review checklist

- Every spec requirement has a task: ABI/layout (Tasks 1-2), lifetime (Task 3),
  admission (Task 4), and evidence/rollback (Tasks 4-5).
- No task admits `list<T>` generally or changes public ownership syntax.
- Positive and negative tests are named, and failure-before-WAT is explicit.
- All file paths are concrete; no TODO/TBD placeholders are required.
- The plan preserves the existing ARC fallback and the 69-fixture behavior as
  the rollback invariant until the new default gate is green.
