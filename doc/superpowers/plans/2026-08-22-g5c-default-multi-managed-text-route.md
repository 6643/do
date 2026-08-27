# G5c C15-D/C16-D Default Multi-Managed-Text Route Plan

> Follow the repository's verification checkpoints. Preserve all unrelated
> dirty worktree changes and do not commit or push without explicit authority.

**Spec:** `doc/superpowers/specs/2026-08-22-g5c-default-multi-managed-text-route-design.md`

**Goal:** Admit only the already verified C15-D lower and C16-D lift
descriptors through ordinary default GC/WIT host calls.

## Constraints

- Reuse the manifest loader, WIT boundary validator, measured plan, and
  ordinary `GcSyncHostWitRoute` bridge.
- Do not add syntax, generic inference, ownership types, async/resource
  lowering, or a compatibility fallback.
- Preserve explicit `--gc-wit-marshal` behavior and all existing C15-B/C16-C
  behavior.
- Leave unadmitted descriptors on their existing route and keep inventory
  `complete_rows=15 pending_rows=15`.

## Tasks

### Task 1: Add the exact default admission rows

**Files:** `src/build/run.zig`, focused unit tests in `src/build/run.zig`.

- [x] Map the C15-D and C16-D locators to their existing descriptor ids.
- [x] Add a unit test for both mappings and an unknown-locator miss.
- [x] Confirm no descriptor-id or measured-layout logic is duplicated in the
  default path.

### Task 2: Add default host and equivalence gates

**Files:**

- `examples/gc-p3-runtime/test_gc_default_host_route_multi.sh`
- `examples/gc-p3-runtime/test_gc_default_host_route_multi_equivalence.sh`

- [x] Build both fixtures without `--gc-wit-marshal`.
- [x] Assert canonical signatures, `;; gc-sync`, no `__arc_`, no GC reference
  at the imports, and lower call-before-free ordering.
- [x] Assemble and validate both Components with the pinned toolchain.
- [x] Run the existing C15-D/C16-D Rust/Wasmtime host adapters.
- [x] Compare default GC Components to the checked-in linear references and
  require `2/2` cleanup for C15-D and `17/17` for C16-D.

### Task 3: Update fail-closed negative gates

**Files:** the C15-D and C16-D compiler boundary negative scripts.

- [x] Keep async and locator mismatch rejection before WAT with no artifact.
- [x] Change only the default-fixture assertions from ARC fallback to the
  manifest-backed GC route.
- [x] Keep explicit opt-in host/equivalence gates and the residual baseline.

### Task 4: Wire the promotion into regression coverage

**Files:** `src/build/test/check_gc_g5c_residual_gate.sh`,
`src/build/test/run_release_smoke.sh` or its wiring test, and documentation.

- [x] Invoke the combined default multi gate from the residual baseline or its
  static wiring test.
- [x] Record the new default boundary and rollback table in the current docs.
- [x] Do not mark the migration inventory complete.

### Task 5: Verify and close the promotion

- [x] Run `git diff --check` and shell syntax checks.
- [x] Run the two default multi gates and four existing C15-D/C16-D compiler
  gates.
- [x] Run `cd src && zig test main.zig` and `./src/build/test/run_tests.sh`.
- [x] Run `cd src && zig build -Doptimize=ReleaseSmall` and release smoke.
- [x] Run the residual baseline and inventory check, retaining the expected
  inventory exit 1 and `complete_rows=15 pending_rows=15`.
- [x] If any promotion gate fails, remove only the two admission rows and
  document the failed evidence; do not alter existing route behavior.

## Completion Gate

The plan is complete only when the default route, explicit route, negative
boundary, host execution, equivalence, full regression, and rollback invariant
are all verified. A successful explicit opt-in gate alone is insufficient.
