# G5c Full-Cutover Staged Design

## Status

Design approved in chat on 2026-09-16. This document defines the staged
closure of the G5c capability inventory. It does not authorize compiler
changes, public syntax, a new manifest shape, or a change to the current
`complete_rows=15 pending_rows=15` state.

## Goal

Close the remaining G5c rows one at a time, using evidence that the currently
admitted source boundary is implemented by the normal Wasm GC route. A row is
closed only after its frozen admitted scope passes the gate profile appropriate
to that row. Unsupported shapes remain rejected before WAT and do not become
implicitly supported as a side effect of closing a row.

## Terminology and boundary

There are two different transitions in the repository:

1. **GC backend cutover** is already closed. Normal `do build` and `do test`
   select the Wasm GC production route; ARC is only an explicit test-only
   equivalence oracle.
2. **G5c inventory cutover** is still open. It records whether every currently
   admitted capability slice has GC evidence. Closing a G5c row does not change
   the backend choice, expose ARC, add ownership syntax, or imply general
   lowering.

The current inventory has fifteen rows, each with a `current implementation
record` and G5a/G5b/G5c status in
`src/build/test/check_gc_migration_inventory.sh`. The current result is
deliberately `complete_rows=15 pending_rows=15` with exit code `1` because all
G5c fields remain pending. Existing private routes, including the
`mixed-text + byte/u32-list lower` host route, are evidence for their exact
shape only; they do not close a broad row by themselves.

## Design principles

- **Freeze before measuring.** Each row's admitted fixture set, current
  rejection boundary, and evidence links are frozen before a G5c run.
- **Evidence before status.** A status change is a consequence of passing the
  row's gates, never an input to make a gate pass.
- **One row per change.** A row gets its own evidence package, focused run,
  status update, and rollback point.
- **Fail closed.** A failed or missing gate leaves the row pending and emits
  the preserved failure evidence. It must not widen a matcher, add a fallback,
  or silently accept a neighboring shape.
- **GC is the only production backend.** No staged row may restore an ARC
  production route. The ARC oracle remains available for equivalence until a
  separate cleanup decision is approved.
- **Canonical boundaries stay linear.** No GC reference crosses a Component or
  WIT canonical boundary; host resources retain explicit ownership/drop
  handling independent of GC reachability.

## State machine

Each row follows the same monotonic state machine:

```text
pending -> candidate -> gc_verified -> closed
```

- `pending`: the row is not yet backed by a complete G5c evidence package.
- `candidate`: the scope and gate profile are frozen and a row-specific run is
  authorized; no status claim is made from a private probe alone.
- `gc_verified`: all gates for the frozen admitted scope have passed, but the
  inventory edit and documentation handoff have not yet been committed.
- `closed`: the inventory links verified evidence and records the row as G5c
  complete.

There is no direct `pending -> closed` transition. If a gate fails, the row
returns to or remains in `pending`; already closed rows are not changed by the
failed row. A private bounded route may enter `candidate` without changing the
row count, but it cannot bypass the row's remaining scope.

## Row gate profiles

The fifteen rows are grouped by the strongest boundary they exercise. The
profile adds gates; it does not remove the common GC checks.

| Profile | Rows | Required evidence |
| --- | --- | --- |
| S: synchronous GC | `text`, `[u8]`, `other_lists`, `managed_struct_list_append`, `managed_structs`, `nested_structs`, `tuple_storage`, `unions`, `generic_calls`, `imports`, `sync_control_flow` | Positive and negative fixtures; default GC compilation; no `__arc_` in the admitted output; root/liveness checks where managed values are involved; ARC/GC equivalence for the frozen scope |
| H: synchronous host/WIT | `host_wit_marshalling`, `host_wit_marshalling_managed_record_lower` | All applicable S gates; fixed manifest/package/member and source hash; measured layout and canonical ABI; no `(ref` at the boundary; Component parse/embed/new/validate; host payload and allocation/free assertions; rollback evidence |
| A: Future/resource | `future_stream_frames`, `resource_terminal_cleanup` | Applicable S gates; GC/linear backend-neutral equivalence; Rust/Wasmtime Future pending/error/cancel/early-drop/repeat lifecycle plus an explicit ready/synchronous-completion rejection boundary; Resource ready/pending/error/cancel/early-drop/repeat lifecycle; exactly-once cleanup; empty `ResourceTable` where the route owns a live table |

The row profile is selected from the current inventory boundary, not from the
most ambitious shape a future implementation might support. For example,
`future_stream_frames` currently covers a bounded sequential `Future<nil>`
slice; it does not become generic `Stream<T>` lowering when the row closes.

## Common gate contract

Every row package must prove all of the following for its frozen scope:

1. **Source scope:** the positive fixtures and all current rejection cases are
   listed; a structural neighbor is rejected before WAT.
2. **Default route:** the ordinary compiler path emits the GC route and the
   admitted output contains no `__arc_` marker.
3. **Memory behavior:** managed values remain reachable across the tested
   branch, call, loop, or suspension boundary; old logical values remain
   observable where the source contract requires value semantics.
4. **Equivalence:** the fixed ARC oracle and GC output agree on the frozen
   observable results. The oracle is a test comparator, not a production
   backend.
5. **Toolchain:** the run records the pinned Zig, rustc, Cargo,
   current-only `wasm-tools`, Wasmtime, and adapter versions plus their
   SHA-256 digests from `toolchain/toolchain.lock.json`; an empty or
   malformed digest is a hard failure.
6. **Reproducibility:** each command, expected exit code, actual exit code, and
   output artifact path is recorded in the evidence package.

The H and A profiles add their profile-specific requirements to this common
contract.

## Execution order

Rows are executed in dependency order so a higher-risk gate cannot conceal a
lower-level regression:

1. **S1 leaf values:** `text`, `[u8]`, `other_lists`.
2. **S2 aggregates and control:** `managed_struct_list_append`,
   `managed_structs`, `nested_structs`, `tuple_storage`, `unions`,
   `generic_calls`, `imports`, `sync_control_flow`.
3. **H host/WIT:** `host_wit_marshalling`,
   `host_wit_marshalling_managed_record_lower`.
4. **A asynchronous/resource:** `future_stream_frames`,
   `resource_terminal_cleanup`.
5. **Inventory handoff:** update only rows whose evidence packages are
   verified, then rerun the complete repository gates.

Each row is an independent commit. A row may be split into smaller commits
for evidence-only preparation and implementation, but a status update must
never be committed without its verified evidence link.

## Evidence package and inventory contract

The existing inventory checker remains the single status gate:
`src/build/test/check_gc_migration_inventory.sh`.

For a G5c-complete row, its TSV `g5c` field becomes `complete` and its G5c
evidence field links only repository-relative files whose first verification
marker is `Verification Status: verified` or `Verification Status: complete`.
For a pending row, the G5c evidence field stays `-`; a pending row must not
fabricate evidence links.

The checker continues to print one line per row and a summary. Until all
fifteen rows are closed, the expected summary remains:

```text
summary complete_rows=15 pending_rows=15
```

with exit code `1`. Only after every row has verified G5c evidence may a
separate, explicitly reviewed change update the expected result to
`complete_rows=15 pending_rows=0` and exit code `0`. That final inventory
change is a release decision, not an automatic side effect of the last route
implementation.

## Rollout and rollback

Before a row run, record the current commit, inventory output, focused gate
outputs, and the exact fixture/evidence set. After a green run, update only
that row's evidence and status and rerun the global gates.

If any gate fails:

- keep the row `pending`;
- preserve the command output and classify the failure as implementation,
  toolchain, environment, or documentation evidence;
- revert only the current row's route/evidence/status changes if necessary;
- leave already closed rows, the GC production route, and the ARC oracle
  unchanged.

Rollback never means restoring ARC as a normal compiler fallback. A failure in
an H or A row also cannot be repaired by widening a synchronous matcher or
claiming that a host side effect was rolled back; cancellation and cleanup
must follow their existing Component contract.

## Documentation and implementation boundaries

The design phase may modify only this spec and its review record. The later
implementation plan may touch, per row, the existing route modules, focused
fixtures, gate scripts, evidence files, and the active status documents. It
must not add:

- public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` syntax;
- general record/list/producer inference or arbitrary producer expressions;
- generic async, borrowed/variant payload, general filesystem async, external
  HTTP, or root hard-cancel lowering;
- a second manifest/ABI layout table or a compatibility route for older tools;
- deletion of `runtime_arc_wat.zig`, `runtime_prelude_wat.zig`,
  `codegen_ownership.zig`, or the ARC equivalence oracle.

The existing exact candidate
`demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower`
is already a bounded default GC/WIT route. This design does not re-implement
or re-promote it; it supplies the inventory-level closure rules that any row
promotion must satisfy.

## Acceptance and stop conditions

The design is accepted when:

- the distinction between backend cutover and inventory cutover is preserved;
- all fifteen rows appear exactly once under a profile;
- every row has a deterministic evidence and rollback contract;
- private bounded evidence cannot close a broader row by implication;
- the intentional `15/15` exit-`1` state remains until a separate final review;
- no user-visible syntax or unmeasured runtime shape is introduced.

The implementation phase must stop at the first missing ABI, lifecycle,
cleanup, root/liveness, or reproducibility fact. A new exact shape that is
not one of the frozen row boundaries requires its own design, pinned probe,
negative fixtures, and approval before any compiler change.

## Source references

- `doc/memory.md`
- `doc/design/2026-08-11-gc-first-memory-decision.md`
- `src/build/test/check_gc_migration_inventory.sh`
- `doc/pending_blocked.md`
- `doc/master_plan.md`
- `doc/start_here.md`
- `doc/roadmap_status.md`
