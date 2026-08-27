# G5c Mixed Scalar-List Record Lower Implementation Plan

> Execute this plan in the current checkout. Preserve all unrelated dirty
> changes. Do not reset, clean, checkout, overwrite, commit, or push unrelated
> files. The design is fixed by
> `doc/superpowers/specs/2026-08-23-g5c-mixed-scalar-list-record-lower-design.md`.

## Goal and fixed contract

Admit exactly one synchronous manifest descriptor:

```text
demo:marshal-record-mixed-scalar-list-lower/api.write@1.0.0/lower
```

Its only accepted Do record is:

```text
Writing { code u32, label text, payload [u8] }
```

The measured root is 20 bytes with fields at offsets `0`, `4`, and `12`. The
canonical host import has five `i32` parameters in field order:
`code, label.ptr, label.len, payload.ptr, payload.len`. The text and byte-list
spans each use `cabi_realloc`; every acquired temporary span is freed once
after the host call. The manifest remains the source of truth and the route
remains synchronous, exact-descriptor based, and fail-closed.

The implementation must not add arbitrary record/list inference, lift,
async/resource/ownership syntax, a new manifest kind, or a compatibility route.
The migration inventory remains `complete_rows=15 pending_rows=15`.

## File map

| Unit | Files | Responsibility |
| --- | --- | --- |
| Typed plan | `src/build/codegen_component_marshal_ops.zig`, `src/build/codegen_gc_plans_test.zig` | Detect the exact three-field shape and expose ordered mixed operations. |
| WAT | `src/build/codegen_component_marshal_wat.zig`, its unit tests | Copy text and byte-list spans, call the five-word import, and free both spans. |
| Boundary | `src/build/codegen_gc_wit_host_boundary.zig`, `src/build/run.zig`, `src/build/codegen_component_manifest_route_test.zig` | Validate the exact Do declaration and ordinary default admission. |
| Descriptor inputs | `doc/wit/gc_descriptor_manifest.json`, `examples/gc-p3-runtime/marshal-record-mixed-scalar-list-lower-manifest-source.wit`, `examples/gc-p3-runtime/marshal-record-mixed-scalar-list-lower-assembly.wit`, `doc/wit/gc_marshal_record_mixed_scalar_list_lower_imports.wit` | Pin source, world, measurement, and Component shape. |
| Compile boundaries | `src/build/test/compile_ok/622_gc_wit_mixed_scalar_list_lower_host_boundary.do`, matching `compile_err` fixtures and `.expect` files | Lock positive and fail-closed source syntax. |
| Runtime evidence | `examples/gc-p3-runtime/ordinary-host-mixed-scalar-list-lower-call.do`, fixed ARC Core oracle, Rust/Wasmtime runner, focused host/equivalence/negative scripts | Prove ABI, value equality, and exactly-once cleanup. |
| Gates/docs | Existing GC default/residual/equivalence/release scripts and the relevant roadmap/blocker docs | Add one bounded fixture without claiming full G5c cutover. |

## Task 1: Add the RED typed-plan and emitter tests

**Files:**

- Modify `src/build/codegen_component_marshal_ops.zig` tests only.
- Modify `src/build/codegen_component_marshal_wat.zig` tests only.
- Modify `src/build/codegen_gc_plans_test.zig` only if the existing manifest-plan
  fixture helper needs a named mixed shape.

First add tests that cannot pass with the current implementation. Build a
measured `Writing` plan with children `u32`, `text`, and byte-list, then assert
that the plan exposes a mixed record descriptor rather than selecting the
existing text-only or scalar-list-only branch:

```zig
try std.testing.expect(memory_plan.record_managed_mixed_scalar_list_lower);
const mixed = memory_plan.managed_mixed_scalar_list_lower orelse unreachable;
try std.testing.expectEqual(@as(u32, 1), mixed.text.field_index);
try std.testing.expectEqual(@as(u32, 2), mixed.scalar_list.field_index);
try std.testing.expectEqual(marshal_ops.ScalarListElementKind.byte, mixed.scalar_list.element_kind);
try std.testing.expectEqual(@as(u32, 1), mixed.scalar_list.element_stride);
try std.testing.expectEqual(@as(u32, 4), mixed.scalar_list.capacity);
```

Assert the operation order is exactly:

```text
read_gc_span,
validate_linear_range,
cabi_realloc_alloc,
copy_to_linear,
validate_linear_range,
cabi_realloc_alloc,
copy_to_linear,
canonical_call,
cabi_realloc_free,
cabi_realloc_free
```

Add the WAT RED assertions for a mixed plan:

- one `array.get_s $do_bytes` and one `i32.store8`;
- two `call $cabi_realloc` occurrences;
- one canonical call with five scalar arguments;
- the first free occurs after the canonical call and the second free occurs
  after the first free;
- no `ref null` value occurs in the import parameter list.

Run the focused tests before writing production code:

```bash
cd src && zig test build/codegen_component_marshal_ops.zig --test-filter mixed
cd src && zig test build/codegen_component_marshal_wat.zig --test-filter mixed
```

Expected RED result: compilation or assertion failure because
`MemoryPlan` has no mixed route and the emitter dispatches only the existing
text/list routes. Fix test setup errors until the failure is caused by the
missing behavior, then leave the RED tests in place.

## Task 2: Add the exact mixed memory-plan shape

**Files:** `src/build/codegen_component_marshal_ops.zig` and focused tests.

Define one internal aggregate that reuses the existing field facts:

```zig
pub const ManagedMixedScalarListLower = struct {
    text: ManagedTextField,
    scalar_list: ManagedScalarListField,
};
```

Add these `MemoryPlan` fields without removing the existing fields:

```zig
record_managed_mixed_scalar_list_lower: bool = false,
managed_mixed_scalar_list_lower: ?ManagedMixedScalarListLower = null,
```

Implement a private `managed_mixed_scalar_list_lower_for_root` guard that
returns a value only for a direct three-child record:

1. root is a measured non-indirect record with exactly three children;
2. child 0 is `u32` with measured `i32`, 4-byte size and 4-byte alignment;
3. child 1 is text with pointer/length facts, 8-byte size and 4-byte
   alignment;
4. child 2 is a one-element byte list with container pointer/length `0/4`,
   container size/alignment `8/4`, element size/alignment/stride `1/1/1`,
   `cabi_realloc` allocation and free, and positive measured capacity;
5. the root measurement is 20 bytes, 4-byte aligned, with root field offsets
   `0`, `4`, and `12` and no indirect result area.

Reuse the existing `ManagedTextField` and `ManagedScalarListField` values; do
not create a second byte-list representation. Change record route selection to
test the mixed guard before the text-only and scalar-list-only guards. For a
matched mixed shape, the selected operation array is the new ten-step array
from Task 1. Every other record keeps its current route or rejection behavior.

Run the RED tests again:

```bash
cd src && zig test build/codegen_component_marshal_ops.zig --test-filter mixed
cd src && zig test build/codegen_gc_plans_test.zig --test-filter mixed
```

Expected result: typed-plan assertions pass while WAT assertions remain RED.

## Task 3: Implement the parameterized mixed WAT lowerer

**Files:** `src/build/codegen_component_marshal_wat.zig` and its tests.

Add `emit_record_lower_managed_mixed_scalar_list` beside the existing managed
text and scalar-list emitters. The function must use the field index and
measured offsets from `ManagedMixedScalarListLower`, not hard-coded local names
or inferred field positions after admission.

Emit this sequence:

1. Read `code` from `struct.get` field 0.
2. Read the text GC array and text length from field 1; guard source span and
   length arithmetic.
3. Allocate text bytes with `cabi_realloc`, copy with `$do_bytes` and
   `i32.store8`.
4. Read the byte-list GC array and list length from field 2; guard source span,
   multiplication by stride 1, and destination range.
5. Allocate payload bytes with `cabi_realloc`, copy with `$do_bytes` and
   `i32.store8`.
6. Call the canonical import with `code`, text pointer/length, and payload
   pointer/length in that order.
7. Free the payload allocation once, then free the text allocation once.

Use explicit locals for both pointers, lengths, and allocation sizes. A zero
length span must remain valid and must still follow the established allocation
and free contract. A trap before allocation must not call the host. A trap after
one allocation must use the existing synchronous cleanup path so no acquired
allocation is leaked. Do not alter top-level list emitters or record lift.

Dispatch the new emitter before the existing managed-text/scalar-list branches.
Run:

```bash
cd src && zig test build/codegen_component_marshal_wat.zig --test-filter mixed
cd src && zig test build/codegen_component_manifest_route_test.zig --test-filter mixed
```

Expected result: all focused mixed tests pass, existing byte-list/u32-list and
managed-text tests remain green, and the generated import has no GC reference.

## Task 4: Pin manifest, WIT, source boundary, and negative fixtures

**Files:**

- Add the three WIT files listed in the file map.
- Add `examples/gc-p3-runtime/ordinary-host-mixed-scalar-list-lower-call.do`.
- Add positive fixture `src/build/test/compile_ok/622_gc_wit_mixed_scalar_list_lower_host_boundary.do`.
- Add matching numbered `compile_err` fixtures for async declaration, locator
  mismatch, member mismatch, reordered fields, `[u32]` payload, `text` payload,
  and an extra fourth field. Each `.expect` file must use the existing
  fail-closed diagnostic class and include the descriptor id.
- Modify `doc/wit/gc_descriptor_manifest.json` by adding one descriptor only.

The manifest entry must use:

```json
{
  "id": "demo:marshal-record-mixed-scalar-list-lower/api.write@1.0.0/lower",
  "source": "examples/gc-p3-runtime/marshal-record-mixed-scalar-list-lower-manifest-source.wit",
  "world_source": "doc/wit/gc_marshal_record_mixed_scalar_list_lower_imports.wit",
  "package": "demo:marshal-record-mixed-scalar-list-lower@1.0.0",
  "world": "probe",
  "interface": "api",
  "member": "write",
  "direction": "lower",
  "params": ["writing"],
  "result": "_",
  "canonical_import": {
    "module": "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0",
    "name": "write"
  }
}
```

Add the measured root and child objects exactly as defined by the spec. Compute
the source hash from the checked-in manifest source and verify it with:

```bash
sha256sum examples/gc-p3-runtime/marshal-record-mixed-scalar-list-lower-manifest-source.wit
```

Do not alter existing descriptor ids, hashes, measurements, or schema fields.

Extend `codegen_gc_wit_host_boundary.zig` with one exact descriptor constant and
the expected field sequence `code u32`, `label text`, `payload [u8]`. Extend
`src/build/run.zig`'s admission table and the route unit tests. The selected
descriptor must fail before writing output when its WIT/Do declaration or
measurement drifts.

Run the positive and negative compiler fixtures directly and verify failed
cases leave no output artifact:

```bash
./bin/do build src/build/test/compile_ok/622_gc_wit_mixed_scalar_list_lower_host_boundary.do -o /tmp/g5c-mixed-scalar-list.wat
for f in src/build/test/compile_err/*mixed_scalar_list*; do ./bin/do build "$f" -o /tmp/should-not-exist.wat && exit 1 || :; done
test ! -e /tmp/should-not-exist.wat
```

## Task 5: Add Component, host, equivalence, and default gates

**Files:**

- Add a fixed linear-memory ARC Core oracle using the same five-word import.
- Add the Rust 2024 Wasmtime runner and equivalence runner under
  `examples/p3-runtime/rust-host-runner/src/bin/`.
- Add focused host, equivalence, and negative shell scripts under
  `examples/gc-p3-runtime/`.
- Modify the repository default-build, residual, semantic-equivalence, and
  release-smoke gate scripts only where they enumerate or inspect admitted
  fixtures.

The positive input constructs `Writing{code = 7, label = "hello", payload =
[10, 20, 5]}`. The host runner must assert one callback, exact field values,
two allocations, and two frees. The equivalence runner must execute the
compiler-generated GC Component and ARC oracle with the same WIT and compare
the observed callback values and result counters.

Every Component artifact must pass the pinned toolchain:

```bash
wasm-tools --version
wasm-tools parse <core.wat> -o <core.wasm>
wasm-tools component embed <wit-dir> <core.wasm> -o <embedded.wasm>
wasm-tools component new <embedded.wasm> -o <component.wasm>
wasm-tools validate <component.wasm>
```

The gate must reject ARC markers and GC references in the canonical import,
check allocation/call/free order, and require the exact host output. Update
the default admitted count by one only after the fixture passes. Keep the
residual gate's expected inventory status unchanged.

## Task 6: Full verification and completion audit

Run all focused tests and gates, preserving full output for any failure:

```bash
cd src && zig test main.zig
./src/build/test/run_tests.sh
cd src && zig build -Doptimize=ReleaseSmall
./src/build/test/run_release_smoke.sh
bash src/build/test/check_gc_default_build_gate.sh
bash src/build/test/check_gc_g5c_residual_gate.sh
bash src/build/test/check_gc_migration_inventory.sh
git diff --check
```

Also run `bash -n` on every new shell script, `cargo fmt --check` for new Rust
bins, and `wasm-tools --version`; the required version is `1.255.0`. Confirm the
focused route, existing C16/byte-list/u32-list routes, and all negative gates
remain green. Confirm the inventory still reports
`complete_rows=15 pending_rows=15` with its documented nonzero status.

Before reporting completion, inspect `git diff --stat`, `git diff --check`, and
`git status --short` to ensure only files belonging to this plan were added or
modified by this work. Do not push automatically; pushing requires a separate
explicit user instruction.
