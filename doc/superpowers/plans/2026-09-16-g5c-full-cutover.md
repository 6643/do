# G5c Full-Cutover Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task with review checkpoints. Steps use checkbox syntax for tracking.

Goal: close the fifteen frozen G5c inventory rows one at a time with reproducible GC, boundary, lifecycle, and rollback evidence, while leaving unsupported shapes fail-closed.

Architecture: the normal compiler route is already Wasm GC-only; this plan closes the separate capability inventory. A small row-gate runner consumes the existing inventory metadata and invokes the current focused probes, equivalence gates, and toolchain checks. Each row receives one verified evidence document and one inventory-only status commit. Any implementation defect is fixed only inside that row's already-admitted boundary; no row may widen a matcher or add a public type.

Tech stack: Zig 0.16.0, wasm-tools 1.258.0, Wasmtime 48.0.1, Rust/Cargo 1.97.1, the repository bin/do-toolchain adapter, Bash gates, WAT/Core-GC probes, Component validation, and the existing Rust Wasmtime runners.

Spec: doc/superpowers/specs/2026-09-16-g5c-full-cutover-design.md

## Global Constraints

- The normal managed-memory route remains Wasm GC-only; ARC is an explicit test-only equivalence oracle.
- Freeze each row's admitted fixtures, rejection boundary, and evidence links before its run.
- A row moves only pending -> candidate -> gc_verified -> closed.
- Until the final row is verified, the inventory remains complete_rows=15 pending_rows=15 with exit code 1.
- No Wasm GC reference crosses a Component/WIT canonical boundary.
- WIT resources retain explicit transfer, borrow, drop, cancellation, and terminal cleanup; GC reachability never replaces resource cleanup.
- Do not add public own<T>, borrow<T>, ref<T>, Option, or Result syntax.
- Do not add generic async, generic Stream<T>, arbitrary producer expressions, general filesystem/HTTP async, borrowed payload lowering, or an older-tool compatibility route.
- Use bin/do-toolchain and toolchain/toolchain.lock.json; active scripts must not invoke an unpinned system wasm-tools directly.
- Preserve runtime_arc_wat.zig, runtime_prelude_wat.zig, codegen_ownership.zig, and the ARC oracle.
- Each row ends with a focused gate, git diff --check, and a local commit. Do not push from this plan.
- A failed row leaves its G5c field pending, preserves its failure log, and does not change already closed rows.

## File And Responsibility Map

- Create src/build/test/check_gc_g5c_row.sh. It reads one row from the existing inventory, runs its profile gates, enforces GC-only/no-ARC/no-GC-reference checks, and writes a reproducible run log. It never edits inventory status.
- Create doc/g5c/evidence/<row>.md for each row. The first line is Verification Status: verified only after every gate for that row passes.
- Modify src/build/test/check_gc_migration_inventory.sh one TSV row at a time: change only that row's g5c field from pending to complete and link its verified evidence document.
- Reuse the existing examples/gc-p3-runtime/test_do_gc_*.sh, examples/gc-p3-runtime/test_gc_*.sh, src/build/test/check_gc_default_build_gate.sh, src/build/test/check_gc_semantic_equivalence.sh, src/build/test/check_gc_arc_inventory.sh, and current Component/Rust runners.
- Modify route modules or focused fixtures only if the row gate reproduces a real defect inside the frozen boundary. Such a change must precede the evidence/status commit and keep the rejection boundary unchanged.
- Modify doc/master_plan.md, doc/roadmap_status.md, doc/pending_blocked.md, doc/start_here.md, and CHANGELOG.md only in the final handoff task.

## Row Matrix And Closure Order

The row names below are the exact first field in src/build/test/check_gc_migration_inventory.sh. The inventory remains the source for each row's positive fixture list, probe list, G5b equivalence list, and current implementation boundary.

| Task | Profile | Row | Frozen rejection boundary | Expected summary after close |
| --- | --- | --- | --- | --- |
| 2 | S | text | UnsupportedGcSyncExpression outside parsed text identity/branch admission | complete_rows=15 pending_rows=14 |
| 3 | S | [u8] | UnsupportedGcSyncExpression or UnsupportedGcSyncType | complete_rows=15 pending_rows=13 |
| 4 | S | other_lists | UnsupportedGcSyncType or UnsupportedGcSyncExpression for spread/multi-value/dynamic/other producers | complete_rows=15 pending_rows=12 |
| 5 | S | managed_struct_list_append | UnsupportedGcSyncType or UnsupportedGcSyncExpression for spread/multi-value/general producers | complete_rows=15 pending_rows=11 |
| 6 | S | managed_structs | UnsupportedGcSyncProducer, UnsupportedGcSyncType, or UnsupportedGcSyncExpression for nested/multi-return/mismatched/async/host/resource producers | complete_rows=15 pending_rows=10 |
| 7 | S | nested_structs | UnsupportedGcSyncProducer, UnsupportedGcSyncExpression, or UnsupportedGcSyncType beyond admitted nested scalar paths | complete_rows=15 pending_rows=9 |
| 8 | S | tuple_storage | UnknownGcSyncLocal, UnsupportedGcSyncExpression, or UnsupportedGcSyncType outside direct Tuple<text,[u8]> rewrite | complete_rows=15 pending_rows=8 |
| 9 | S | unions | General @is binding and payload-union shapes remain rejected | complete_rows=15 pending_rows=7 |
| 10 | S | generic_calls | Unresolved bindings, generic field/layout instantiation, and resource shapes remain rejected | complete_rows=15 pending_rows=6 |
| 11 | S | imports | Unsupported module graphs, host/WIT, and async imports remain rejected | complete_rows=15 pending_rows=5 |
| 12 | S | sync_control_flow | UnsupportedGcSyncControl or UnsupportedGcSyncStatement for loops and other unadmitted control flow | complete_rows=15 pending_rows=4 |
| 13 | H | host_wit_marshalling | Arbitrary/general aggregates, unpinned layouts, and async/resource shapes remain rejected | complete_rows=15 pending_rows=3 |
| 14 | H | host_wit_marshalling_managed_record_lower | General managed-record lower and async/resource shapes remain rejected | complete_rows=15 pending_rows=2 |
| 15 | A | future_stream_frames | UnsupportedGcSyncAsync; generic async, general Stream, and host-future cancellation remain rejected | complete_rows=15 pending_rows=1 |
| 16 | A | resource_terminal_cleanup | UnsupportedGcSyncAggregate or UnsupportedGcSyncType; generic resource/borrowed payload remains rejected | complete_rows=15 pending_rows=0 |

## Common Row-Gate Contract

The runner created in Task 1 has this exact interface:

    bash src/build/test/check_gc_g5c_row.sh \
      --row '<inventory-row>' \
      --profile S|H|A \
      --evidence-dir '<existing-directory>'

It must:

1. Resolve the requested row from the inventory here-document, require exactly nine TSV fields, require g5c=pending, and verify every linked G5a fixture, probe, and G5b evidence path exists.
2. Record git rev-parse HEAD, the branch, inventory output, and versions/hashes from bin/do-toolchain probe and toolchain/toolchain.lock.json in evidence-dir/commands.log.
3. Run src/build/test/check_gc_arc_inventory.sh --post-cutover, src/build/test/check_gc_default_build_gate.sh, and src/build/test/check_gc_migration_evidence_test.sh. The first two must pass; the inventory status command is expected to return 1 before final closure.
4. Run every comma-separated G5a probe and every comma-separated G5b script in the selected row. A non-zero probe stops that row and preserves its log.
5. For H, require every generated boundary artifact checked by the invoked gate to contain no (ref in the canonical import and to pass Component parse/embed/new/validate. For A, require the invoked runner's ready/pending/error/cancel/early-drop/repeat observations and exactly-once cleanup where that row defines them.
6. Write a deterministic summary containing row, profile, commands, expected and actual exit codes, toolchain versions, output-log paths, and the frozen rejection boundary. It must not write the inventory file.

The runner fails closed for an unknown row, profile mismatch, missing file, non-pending row, unpinned toolchain, ARC marker in admitted WAT, GC reference at a canonical boundary, or an unexpected gate exit code. It must not delete a failed run directory.

### Task 1: Establish The Row-Gate Runner And Baseline

Files:
- Create src/build/test/check_gc_g5c_row.sh
- Create doc/g5c/evidence/.gitkeep
- Test src/build/test/check_gc_g5c_row.sh, src/build/test/check_gc_migration_inventory.sh, src/build/test/check_gc_arc_inventory.sh

Interfaces:
- Consumes the nine-column inventory rows and the pinned toolchain lock.
- Produces the row runner used by Tasks 2-16.

- [ ] Step 1: Write the failing invocation.

    run_dir="$(mktemp -d)"
    if bash src/build/test/check_gc_g5c_row.sh --row text --profile S --evidence-dir "$run_dir"; then
        printf 'row runner unexpectedly exists before implementation\n' >&2
        exit 1
    fi

Expected: failure because the runner does not exist.

- [ ] Step 2: Implement the parser and gate dispatch.

Use awk -F '\t' to extract only the requested row between the inventory here-document markers. Parse all nine fields, split comma-separated paths without word-splitting path contents, and reject a non-pending row before invoking a route. Use an explicit case for S, H, and A. Run commands through bash, bin/do-toolchain, or the pinned paths in the lock.

- [ ] Step 3: Verify the baseline.

    run_dir="$(mktemp -d)"
    bash src/build/test/check_gc_g5c_row.sh --row text --profile S --evidence-dir "$run_dir"
    set +e
    bash src/build/test/check_gc_migration_inventory.sh
    rc=$?
    set -e
    test "$rc" -eq 1

Expected: the row runner creates commands.log and a summary, and the inventory prints complete_rows=15 pending_rows=15 with exit 1.

- [ ] Step 4: Commit the runner only.

    git add src/build/test/check_gc_g5c_row.sh doc/g5c/evidence/.gitkeep
    git diff --cached --check
    git commit -m "Add G5c row evidence gate"

### Task 2: Close text

Files:
- Create doc/g5c/evidence/text.md
- Modify only the text TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_do_gc_text_identity.sh, test_do_gc_text_identity_renamed.sh, test_do_gc_text_branch.sh

Interfaces:
- Consumes the Task 1 runner and the three inventory probes.
- Produces one verified evidence document and one closed text G5c field.

- [ ] Step 1: Run the frozen row gate.

    run_dir="$(mktemp -d)"
    bash src/build/test/check_gc_g5c_row.sh --row text --profile S --evidence-dir "$run_dir"

Record actual HEAD, command-log path, probe results, toolchain versions, and the preserved rejection boundary in doc/g5c/evidence/text.md. The first line is Verification Status: verified only when the command exits 0.

- [ ] Step 2: Update only the text inventory fields.

Change its g5c field to complete and its evidence field to doc/g5c/evidence/text.md. Do not alter its G5a/G5b fields, boundary text, or any other row.

- [ ] Step 3: Verify and commit.

    set +e
    bash src/build/test/check_gc_migration_inventory.sh
    rc=$?
    set -e
    test "$rc" -eq 1
    rg -q 'summary complete_rows=15 pending_rows=14' <(bash src/build/test/check_gc_migration_inventory.sh 2>&1) || true
    git add doc/g5c/evidence/text.md src/build/test/check_gc_migration_inventory.sh
    git diff --cached --check
    git commit -m "Close G5c text row"

If any gate fails, do not change the TSV row; preserve the failed run log and leave the row pending.

### Task 3: Close [u8]

Files:
- Create doc/g5c/evidence/u8.md
- Modify only the [u8] TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_do_gc_list_set.sh, test_do_gc_parameterized_list_set.sh, test_do_gc_list_literal.sh, test_do_gc_list_put.sh

- [ ] Step 1: Run bash src/build/test/check_gc_g5c_row.sh --row '[u8]' --profile S --evidence-dir "$run_dir" with a fresh mktemp directory. Record every actual probe and equivalence result.
- [ ] Step 2: Set only [u8]'s g5c fields, require summary complete_rows=15 pending_rows=13 and checker exit 1, run git diff --check, and commit with message Close G5c byte-list row.

### Task 4: Close other_lists

Files:
- Create doc/g5c/evidence/other_lists.md
- Modify only the other_lists TSV row in src/build/test/check_gc_migration_inventory.sh
- Test every probe listed in the other_lists TSV row, including remaining scalar lists, text-list put, nested byte-list put, scalar-list put, inferred list storage, and inferred u32 list storage.

- [ ] Step 1: Run bash src/build/test/check_gc_g5c_row.sh --row other_lists --profile S --evidence-dir "$run_dir" with a fresh mktemp directory. Record the complete scalar/text/nested probe count and the rejection boundary.
- [ ] Step 2: Set only other_lists' g5c fields, require summary complete_rows=15 pending_rows=12 and checker exit 1, run git diff --check, and commit with message Close G5c scalar-list row.

### Task 5: Close managed_struct_list_append

Files:
- Create doc/g5c/evidence/managed_struct_list_append.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_do_gc_managed_struct_list.sh

- [ ] Step 1: Run the row gate with --row managed_struct_list_append --profile S and capture the bounded [Box] one-value @put lifecycle output.
- [ ] Step 2: Write verified evidence, update only this row, require summary complete_rows=15 pending_rows=11, run git diff --check, and commit with message Close G5c managed-struct-list row.

### Task 6: Close managed_structs

Files:
- Create doc/g5c/evidence/managed_structs.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test every probe listed in the managed_structs TSV row, including direct payload, field-call producer, renamed, preserve-field, set, and remaining scalar-field probes.

- [ ] Step 1: Run bash src/build/test/check_gc_g5c_row.sh --row managed_structs --profile S --evidence-dir "$run_dir" and record all actual outputs.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=10, run git diff --check, and commit with message Close G5c managed-struct row. Preserve rejection of nested/multi-return/mismatched/async/host/resource producers.

### Task 7: Close nested_structs

Files:
- Create doc/g5c/evidence/nested_structs.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test test_do_gc_nested_managed_struct.sh, test_do_gc_two_level_nested_field_path.sh, test_do_gc_three_level_nested_field_path.sh, test_do_gc_four_level_nested_field_path.sh, and test_do_gc_five_level_nested_field_path.sh.

- [ ] Step 1: Run the exact one- through five-level matrix with --row nested_structs --profile S and record the depth-specific outputs.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=9, run git diff --check, and commit with message Close G5c nested-struct row. Preserve rejection of deeper paths and other nested aggregates.

### Task 8: Close tuple_storage

Files:
- Create doc/g5c/evidence/tuple_storage.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_do_gc_managed_tuple_text_bytes.sh

- [ ] Step 1: Run the tuple gate with --row tuple_storage --profile S and record direct Tuple<text,[u8]> get/rewrite output and the UnknownGcSyncLocal rejection boundary.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=8, run git diff --check, and commit with message Close G5c tuple-storage row.

### Task 9: Close unions

Files:
- Create doc/g5c/evidence/unions.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_do_gc_payload_union.sh

- [ ] Step 1: Run the union gate with --row unions --profile S and record Unit | Bytes([u8]), direct tag comparison, defer, and @len observations.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=7, run git diff --check, and commit with message Close G5c union row. Preserve general @is binding rejection.

### Task 10: Close generic_calls

Files:
- Create doc/g5c/evidence/generic_calls.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_do_gc_generic_managed_identity.sh

- [ ] Step 1: Run the generic identity gate with --row generic_calls --profile S and record resolved identity output and unresolved-binding rejection.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=6, run git diff --check, and commit with message Close G5c generic-call row.

### Task 11: Close imports

Files:
- Create doc/g5c/evidence/imports.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_do_gc_imported_text_identity.sh

- [ ] Step 1: Run the imported identity gate with --row imports --profile S and record file-backed GC/ARC equivalence output.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=5, run git diff --check, and commit with message Close G5c imported-value row. Preserve unsupported module-graph, host/WIT, and async rejection.

### Task 12: Close sync_control_flow

Files:
- Create doc/g5c/evidence/sync_control_flow.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_do_gc_text_branch.sh, test_do_gc_scalar_control_flow.sh, and test_do_gc_scalar_call_graph.sh.

- [ ] Step 1: Run --row sync_control_flow --profile S and record branch-join, bounded defer, and call-graph observations.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=4, run git diff --check, and commit with message Close G5c synchronous-control row. Preserve UnsupportedGcSyncControl and UnsupportedGcSyncStatement for unadmitted loops.

### Task 13: Close host_wit_marshalling

Files:
- Create doc/g5c/evidence/host_wit_marshalling.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test every host probe and equivalence script listed in the host_wit_marshalling TSV row, including the default mixed text/byte/u32 lower host, equivalence, and negative gates.

- [ ] Step 1: Run bash src/build/test/check_gc_g5c_row.sh --row host_wit_marshalling --profile H --evidence-dir "$run_dir".
- [ ] Step 2: Record WIT source hashes, measured layouts, generated WAT/component artifact paths, no-(ref) boundary results, host payload/allocation/free counters, and every resolved host/equivalence command in the evidence document.
- [ ] Step 3: Update only this row, require summary complete_rows=15 pending_rows=3, run git diff --check, and commit with message Close G5c host-WIT marshalling row. A private mixed-text/byte/u32 route cannot close absent shapes.

### Task 14: Close host_wit_marshalling_managed_record_lower

Files:
- Create doc/g5c/evidence/host_wit_marshalling_managed_record_lower.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test test_gc_marshal_record_managed_lower_manifest_host.sh, test_gc_marshal_record_managed_lower_multi_manifest_host.sh, test_gc_marshal_record_managed_lower_multi_compiler_host.sh, and their three listed equivalence gates.

- [ ] Step 1: Run --row host_wit_marshalling_managed_record_lower --profile H and record exact {u32,text} and {u32,text,text} lower paths plus the pinned multi-record compiler boundary.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=2, run git diff --check, and commit with message Close G5c managed-record lower row. Keep general managed-record lower pending by rejection.

### Task 15: Close future_stream_frames

Files:
- Create doc/g5c/evidence/future_stream_frames.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_gc_async_frame_component.sh and test_gc_async_frame_equivalence.sh.

- [ ] Step 1: Run --row future_stream_frames --profile A and record ready/pending/wake/completion observations, GC/linear comparison, frame/table markers, and AsyncLoweringUnavailable for unsupported ordinary async source.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=1, run git diff --check, and commit with message Close G5c Future-frame row.

### Task 16: Close resource_terminal_cleanup

Files:
- Create doc/g5c/evidence/resource_terminal_cleanup.md
- Modify only this TSV row in src/build/test/check_gc_migration_inventory.sh
- Test examples/gc-p3-runtime/test_gc_resource_terminal_cleanup.sh and examples/p3-runtime/test_rust_resource_cancellation_shape.sh.

- [ ] Step 1: Run --row resource_terminal_cleanup --profile A and record ready/pending/error/cancel/early-drop/repeat behavior, exactly-once cleanup counters, terminal ResourceTable state, and the no-rollback cancellation rule.
- [ ] Step 2: Update only this row, require summary complete_rows=15 pending_rows=0, run git diff --check, and commit with message Close G5c resource cleanup row.

The checker must return 0 and print complete_rows=15 pending_rows=0. If it returns 1 or 2, do not alter final status documentation; preserve the failure evidence and stop this task.

### Task 17: Final Inventory Review And Documentation Handoff

Files:
- Modify doc/master_plan.md
- Modify doc/roadmap_status.md
- Modify doc/pending_blocked.md
- Modify doc/start_here.md
- Modify CHANGELOG.md
- Test all repository gates and the final inventory checker

Interfaces:
- Consumes fifteen verified evidence documents, fifteen row commits, and fresh final command output.
- Produces synchronized release documentation distinguishing GC backend cutover from completed G5c inventory cutover.

- [ ] Step 1: Run the complete final verification matrix.

    ./src/build/test/run_tests.sh
    (cd src && zig test main.zig)
    (cd src && zig build -Doptimize=ReleaseSmall)
    ./src/build/test/run_release_smoke.sh
    bash src/build/test/check_gc_arc_inventory.sh --post-cutover
    bash src/build/test/check_gc_default_build_gate.sh
    bash src/build/test/check_gc_semantic_equivalence.sh
    bash src/build/test/check_gc_migration_evidence_test.sh
    bash src/build/test/check_gc_migration_inventory.sh

All commands must exit 0; the last command must print complete_rows=15 pending_rows=0. Record actual fixture/test counts and toolchain versions; do not copy earlier counts.

- [ ] Step 2: Update active status documents from fresh output.

State that GC backend cutover and G5c inventory cutover are separate, list all fifteen verified evidence paths, retain unsupported-shape boundaries, and remove only the superseded deliberate pending_rows=15 wording. Do not claim generic async, generic Stream, public ownership syntax, or general WASI support.

- [ ] Step 3: Run consistency checks.

    git diff --check
    rg -n 'complete_rows=15 pending_rows=0|G5c|GC-only|ARC.*oracle|own<T>|borrow<T>|ref<T>|generic async|generic Stream' doc/master_plan.md doc/roadmap_status.md doc/pending_blocked.md doc/start_here.md CHANGELOG.md
    git status --short

Expected: no whitespace errors, no contradictory active pending_rows=15 claim, no accidental public ownership/generic-async claim, and only planned paths modified.

- [ ] Step 4: Commit the final handoff locally.

    git add doc/master_plan.md doc/roadmap_status.md doc/pending_blocked.md doc/start_here.md CHANGELOG.md doc/g5c/evidence
    git diff --cached --check
    git commit -m "Close G5c capability inventory"

Do not push in this plan. Push is a separate delivery decision after review of the fifteen row commits and final verification output.

## Failure, Rollback, And Stop Conditions

- A failed row gate produces no inventory status change. Keep the failed run directory and add its command/output path to a dated failure note under doc/g5c/failures/; do not mark the evidence document verified.
- If a focused implementation fix is needed, add a failing fixture or assertion first, change only the row's existing route, rerun that row's complete profile, and commit the implementation separately before the evidence/status commit.
- A row failure must not restore ARC in the normal compiler, widen an existing matcher, alter the public language, or change another row's evidence.
- Stop for a missing ABI/hash, a GC reference crossing a canonical boundary, a liveness/root failure, a resource cleanup mismatch, an unexpected tool version, or a silent diagnostic change. Record evidence and request a new design decision if the frozen boundary is insufficient.
- After any implementation change, rerun ./src/build/test/run_tests.sh, (cd src && zig test main.zig), the relevant profile gates, and the migration checker before resuming the next row.

## Plan Self-Review

- Spec coverage: the plan includes the boundary distinction, state machine, three gate profiles, fifteen-row order, evidence contract, rollback rules, final handoff, and all explicit non-goals.
- Placeholder scan: every row has a named source boundary, exact runner invocation, evidence file, expected inventory result, and commit command; no unspecified implementation step is present.
- Contract consistency: the runner interface is fixed as --row, --profile, and --evidence-dir; profile values are exactly S, H, and A; inventory status changes are pending to complete with verified markdown evidence.
