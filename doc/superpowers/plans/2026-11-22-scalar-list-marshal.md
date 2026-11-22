# Scalar List Marshal Plan

## 1. Lock the contract with tests

- Add measured lower and lift cases for `list<u16>`, `list<i64>`, `list<f32>`,
  and `list<bool>`.
- Assert the existing `list<u8>` and `list<u32>` output remains unchanged.
- Assert a size, alignment, stride, or core-word mismatch is rejected.
- Assert zero length still emits the normal allocation, call, and free order.

## 2. Generalize the measured operation plan

- Derive a scalar element layout from the WIT scalar kind.
- Store the element kind in `MemoryPlan`.
- Validate measured child and list facts against the derived layout.

## 3. Generalize WAT emission

- Select the typed GC array and linear load/store instructions from the element
  kind.
- Keep the canonical import as `(ptr, len)` in both directions.
- Keep checked span arithmetic and post-call frees intact.

## 4. Wire module type declarations

- Emit only the scalar GC array type required by the route.
- Preserve existing record and map type emission conditions.

## 5. Verify the boundary

- Run focused Zig tests for operation plans and WAT.
- Run the full regression harness and ReleaseSmall build/smoke.
- Review the diff for accidental changes to the pre-existing worktree edit.
