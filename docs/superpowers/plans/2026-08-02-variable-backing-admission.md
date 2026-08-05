# Variable Backing Admission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the checked byte-budget formulas for text and list backing to a reusable compiler-side allocation model with transactional admission and exact-once release.

**Architecture:** Keep `ByteBudget` as the instance-owned accounting source. Add one variable-size allocation pool that computes a text or list backing charge before reserving bytes, then returns the existing `Allocation` token; the pool only tracks compiler-side model state and does not alter the active ARC runtime or public source syntax.

**Tech Stack:** Zig compiler model and `std.testing`.

## Global Constraints

- Preserve checked overflow and no-mutation-on-rejection semantics.
- Reuse `bytes_for_text_backing` and `bytes_for_list_backing`; do not duplicate arithmetic.
- Keep `own<T>`, `borrow<T>`, `ref<T>`, pointers, and references unsupported in source syntax.
- Do not claim runtime ARC/GC allocation integration or configurable Component quota.
- Verify focused Zig tests, release build, full regression, and whitespace checks.

---

### Task 1: Red Tests For Variable Backing Pools

**Files:**
- Modify: `src/build/async_byte_budget_test.zig`

**Interfaces:**
- Produce `TextBackingPool.init(budget, header_bytes)`, `acquire(utf8_bytes)`, `release(allocation)`.
- Produce `ListBackingPool.init(budget, header_bytes, elem_bytes)`, `acquire(capacity)`, `release(allocation)`.

- [x] **Step 1: Add tests for text and list admission.**

```zig
test "variable backing pools reserve by capacity and release exactly once" {
    var bytes = budget.ByteBudget.init(40);
    var text = budget.TextBackingPool.init(&bytes, 8);
    var text_allocation = try text.acquire(24);
    try std.testing.expectEqual(@as(u64, 32), bytes.committed_bytes());
    try std.testing.expectError(error.ByteBudgetExceeded, text.acquire(9));
    try std.testing.expectEqual(@as(u64, 32), bytes.committed_bytes());
    try text.release(&text_allocation);

    var list = budget.ListBackingPool.init(&bytes, 8, 4);
    var list_allocation = try list.acquire(8);
    try std.testing.expectEqual(@as(u64, 40), bytes.committed_bytes());
    try list.release(&list_allocation);
    try std.testing.expectEqual(@as(u64, 0), bytes.committed_bytes());
    try std.testing.expectError(error.AllocationInvariantViolation, list.release(&list_allocation));
}
```

- [x] **Step 2: Run the focused test and confirm the missing API fails.**

Run: `cd src && zig test build/async_byte_budget_test.zig --test-filter 'variable backing pools'`

Expected: compile failure naming the missing `TextBackingPool` or `ListBackingPool`.

### Task 2: Implement The Shared Variable Allocation Model

**Files:**
- Modify: `src/build/async_byte_budget.zig`

**Interfaces:**
- `TextBackingPool` computes `bytes_for_text_backing(header_bytes, utf8_bytes)` before reservation.
- `ListBackingPool` computes `bytes_for_list_backing(header_bytes, elem_bytes, capacity)` before reservation.
- Both return the existing `Allocation` token and reject foreign or already released tokens through the existing invariant errors.

- [x] **Step 1: Add a private variable allocation pool.**

The helper stores `budget`, `active_allocations`, and an allocation-kind-specific byte calculator. It must reserve and commit before incrementing the live count; if the count overflows, release the committed token and return `ByteSizeOverflow`.

- [x] **Step 2: Add text/list wrappers using the checked formulas.**

The wrappers must set the allocation owner to their own pool, so a release through a different pool returns `AllocationInvariantViolation`. A failed size formula or budget reservation must not change `active_allocations`, `committed`, or `reserved`.

### Task 3: Verify And Record The Boundary

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `docs/superpowers/plans/2026-08-02-variable-backing-admission.md`

- [x] **Step 1: Run focused Zig tests and strict source checks.**

Run: `cd src && zig test build/async_byte_budget_test.zig && zig build -Doptimize=ReleaseSmall`; then run `git diff --check` and the full `./src/build/test/run_tests.sh` gate.

- [x] **Step 2: Record the exact boundary.**

Document that text/list backing now has a transactional compiler-side allocation model, while generated ARC/GC allocation call sites, generic endpoint storage, scheduler policy, and public Component quota remain outside the implementation.
