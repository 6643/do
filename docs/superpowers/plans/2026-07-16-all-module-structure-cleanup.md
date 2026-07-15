# All Module Structure Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the repository-wide structural cleanup across the standard library, compiler, tooling, tests, and current documentation without changing language semantics, WAT/WASI ABI, ownership behavior, or public library contracts.

**Architecture:** Keep the repository flat. Standard-library files remain public module units; compiler modules are split by ownership and one-way dependencies; tooling keeps small command boundaries; documentation distinguishes current sources from historical plans. Each task ends with a focused check and the full regression gate before the next task.

**Tech Stack:** Zig, Bash, Node.js, `.do` standard-library modules, WAT fixtures, and `./src/build/test/run_tests.sh`.

## Global Constraints

- Preserve language semantics, parser grammar, diagnostics, generated WAT, WASI ABI layout, ARC/runtime behavior, ownership behavior, and public standard-library names.
- Keep `src/build/` flat; do not add `src/build/codegen/`, `src/build/sema/`, or generic `common.zig`/`util.zig` buckets.
- Preserve `codegen_api.zig` and `sema.zig` as stable public entry boundaries.
- Use lowercase snake_case for project-defined Zig identifiers; do not rename Zig standard-library methods.
- Keep historical `CHANGELOG.md`, design, and completed-plan references intact; update only current-state documentation.
- Run `./src/build/test/run_tests.sh`, `./src/build/test/check_module_boundaries.sh`, and `git diff --check` at every checkpoint.

## Baseline

```bash
./src/build/test/run_tests.sh
./src/build/test/check_module_boundaries.sh
git diff --check
```

Expected baseline: `pass=941 fail=0 skip=3`, clean worktree, and no old compiler module files.

## Task 1: Current-state documentation and boundary guard

Status: completed; current-state documentation is synchronized. The boundary guard will be extended with the later ownership checks after those module moves exist.

**Files:**
- Modify: `README.md`, `doc/spec.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/memory.md`, `src/build/test/README.md`
- Modify: `src/build/test/check_module_boundaries.sh`
- Test: `./src/build/test/run_tests.sh`

- [ ] Refresh current module maps and test baselines to the checked-out structure.
- [ ] Leave historical sections and historical plans unchanged.
- [ ] Extend the boundary guard with explicit owner checks for the new codegen and sema boundaries.
- [ ] Run the full regression and documentation residual scan.

## Task 2: Standard-library network ownership

Status: skipped as an architecture blocker. `sema_imports.zig` validates WIT host types against declarations in the current file (`has_public_struct_decl` / `has_public_payload_enum_decl`); imported `@lib` type aliases are not accepted in host signatures. Sharing these types would require a language/compiler semantic change, outside this refactor.

**Files:**
- Modify: `lib/net.do`, `lib/tcp.do`, `lib/udp.do`
- Test: `src/build/test/compile_ok/291_wasi_tcp_create_union.do` through `297_wasi_tcp_create_dynamic_family.do`

- [ ] Move shared socket address declarations and constructors to `lib/net.do`.
- [ ] Import the shared declarations from `tcp.do` and `udp.do` while preserving their existing public names.
- [ ] Verify socket WAT and ABI output is byte-for-byte compatible with the existing expectations.

## Task 3: Codegen WASI helper ownership

Status: completed; pure storage/type/layout helpers now live in their physical owners, storage layout no longer imports the WASI emitter, and the full regression remains green.

**Files:**
- Modify: `src/build/codegen_emit_wasi.zig`, `src/build/codegen_storage_layout.zig`
- Modify: direct codegen callers currently importing helper aliases
- Test: socket ABI fixture and `zig test src/build/codegen_api.zig`

- [x] Move generic type compatibility, wasm type, payload-width, storage-type, and Tuple-layout helpers to `codegen_storage_layout.zig`.
- [x] Keep `codegen_emit_wasi.zig` limited to WASI argument/result lowering and ABI packing.
- [x] Remove the reverse `codegen_storage_layout -> codegen_emit_wasi` dependency.
- [x] Preserve all helper signatures used by codegen through direct owner imports.

## Task 4: Codegen pipeline facade reduction

Status: completed; pipeline now exposes orchestration and stable WAT entrypoints while generic, storage/layout, token/import, and WASI helper access stays at physical owners.

**Files:**
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/codegen_generics.zig`, `codegen_emit_call.zig`, `codegen_emit_expression.zig`, `codegen_emit_control.zig`, `codegen_emit_union.zig`, and affected tests
- Test: `src/build/test/check_module_boundaries.sh`, full regression

- [x] Keep pipeline orchestration, hook installation, and public WAT entry points.
- [x] Replace broad generic/storage/WASI re-exports with direct imports from physical owners.
- [x] Keep only re-exports required by the stable API or explicit unit-test boundary.
- [x] Confirm no leaf module imports `codegen_pipeline.zig`.

## Task 5: Sema boundary cleanup

Status: completed; control flow, field reflection, and constraints/assignment now have separate flat owners, with token mechanics shared through `sema_tokens.zig`.

**Files:**
- Create: `src/build/sema_control_flow.zig`, `src/build/sema_field_checks.zig`, `src/build/sema_constraints.zig`
- Modify: `src/build/sema_control.zig`, `src/build/sema.zig`, `src/build/sema_tokens.zig`, `src/build/sema_function_support.zig`
- Test: `src/build/test/err`, `src/build/test/compile_err`, full regression

- [x] Move defer/loop/label checks to `sema_control_flow.zig`.
- [x] Move field reflection checks to `sema_field_checks.zig`.
- [x] Move constraint and assignment checks to `sema_constraints.zig`.
- [x] Keep `sema.zig` as the orchestration entry.
- [x] Split token mechanics from language-name predicates only where direct ownership is proven; do not create a generic sema facade.

## Task 6: Module graph and import resolution

**Files:**
- Create: `src/build/module_graph.zig`, `src/build/import_resolution.zig`
- Modify: `src/build/imports.zig`, `src/build/diagnostics.zig`, and direct callers
- Test: import-cycle, visibility, alias, and missing-target fixtures

- [ ] Move path resolution, loading, and graph reachability to `module_graph.zig`.
- [ ] Move alias, visibility, and import semantic checks to `import_resolution.zig`.
- [ ] Keep one-way sema/import ownership and avoid reintroducing a broad `imports` facade.

## Task 7: Test evaluator separation

**Files:**
- Create: `src/build/test_eval.zig`, `src/build/test_values.zig`
- Modify: `src/build/test_runner.zig`, `src/build/test_runner.zig` callers
- Test: all `ok`, `err`, `compiled_ok`, `compiled_err`, `fmt`, `check`, and `lsp` cases

- [ ] Keep discovery, scheduling, and reporting in `test_runner.zig`.
- [ ] Move expression/function evaluation to `test_eval.zig`.
- [ ] Move Value/Binding/struct-value operations to `test_values.zig`.
- [ ] Preserve the single shell entrypoint and summary counts.

## Task 8: LSP helper deduplication

**Files:**
- Create: `src/lsp/source_helpers.zig`
- Modify: `src/lsp/completion.zig`, `definition.zig`, `hover.zig`, `semantic_tokens.zig`, `workspace.zig`
- Test: `./src/build/test/run_tests.sh` LSP cases

- [ ] Move duplicated name classification, line slicing, declaration-head, and token-range helpers to `source_helpers.zig`.
- [ ] Keep protocol serialization and server transport unchanged.
- [ ] Do not add rename/references/incremental-index functionality in this refactor.

## Task 9: Naming and final repository closeout

**Files:**
- Modify: project-defined aliases in `src/build/*.zig`, current docs, `docs/superpowers/plans/2026-07-15-codegen-structure-naming-implementation-plan.md`
- Test: residual scans and full regression

- [ ] Rename remaining project-defined lowerCamel aliases to snake_case.
- [ ] Do not rename Zig standard-library methods such as `appendSlice` or `toOwnedSlice`.
- [ ] Mark the prior implementation plan complete without rewriting its historical file names.
- [ ] Run the final module, naming, stale-reference, and regression checks.

## Final Verification

```bash
cd src && zig build -Doptimize=ReleaseSmall
cd ..
./src/build/test/check_module_boundaries.sh
./src/build/test/run_tests.sh
git diff --check
```

Required result: `pass=941 fail=0 skip=3`, no unresolved conflict markers, no old compiler module paths in current documentation, and a clean worktree.
