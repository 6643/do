# Compiler Structure and Naming Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the compiler implementation under `src/build` around explicit phase/domain boundaries and convert internal Zig function names to lowercase snake_case without changing language behavior, WASI ABI, runtime behavior, or generated instruction strategy.

**Architecture:** Keep the flat `src/build` directory. Establish `codegen_api -> codegen_pipeline -> collect/model/context -> emit -> wat/runtime` as the codegen direction. Remove broad facades, split shared model/context/constants, and keep callback contracts in `codegen_callbacks`.

**Tech Stack:** Zig, Bash, Node.js, `wasm-tools`, existing `.do` fixtures, and the repository regression harness.

## Global Constraints

- Scope is limited to the compiler implementation under `src/build`, plus the structural guard and architecture documentation needed to describe it.
- Do not change language semantics, parser grammar, WIT signatures, WASI ABI layout, ARC behavior, standard-library interfaces, allocation strategy, or generated instruction strategy.
- Preserve existing dirty worktree files: `AGENTS.md`, socket ABI changes, `lib/tcp.do`, `lib/udp.do`, tests, `a.md`, and the async design note.
- Keep the `src/build` directory flat; do not introduce `src/build/codegen/` or `src/build/sema/` directories.
- Use lowercase snake_case for internal Zig functions, PascalCase for types, and UPPER_SNAKE_CASE for constants.
- Do not stage or commit unrelated user changes.
- When a task touches a file that already contains user changes, stage only the refactor hunks with `git add -p`; never use `git add src/build` or `git add -A`.
- Every implementation task ends with `zig test`, the full regression harness, and `git diff --check` unless the task explicitly states a smaller focused command before the full checkpoint.
- Performance optimization is out of scope. Do not cache lookups, reduce allocations, or alter WAT instruction sequences in this plan.

## Planned File Structure

| Current file | Planned file/role |
| --- | --- |
| `src/build/gen.zig` | `src/build/codegen_api.zig`; public entry points only |
| `src/build/gen_lower.zig` | `src/build/codegen_pipeline.zig`; orchestration only |
| `src/build/gen_types.zig` | `src/build/codegen_model.zig`, `src/build/codegen_context.zig`, `src/build/codegen_constants.zig` |
| `src/build/gen_util.zig` | `src/build/codegen_tokens.zig`, `src/build/codegen_names.zig` |
| `src/build/gen_collect.zig` | deleted facade; direct imports from owning collect modules |
| `src/build/gen_collect_func.zig` | `src/build/codegen_collect_functions.zig` |
| `src/build/gen_collect_struct.zig` | `src/build/codegen_collect_structs.zig` |
| `src/build/gen_collect_type.zig` | `src/build/codegen_collect_declarations.zig` |
| `src/build/gen_expr_collect.zig` | `src/build/codegen_collect_body.zig` |
| `src/build/gen_expr.zig` | `src/build/codegen_emit_expression.zig` and `src/build/codegen_emit_call.zig` |
| `src/build/gen_ctrl.zig` | `src/build/codegen_emit_control.zig` |
| `src/build/gen_storage.zig` | `src/build/codegen_emit_storage_values.zig`, `src/build/codegen_emit_storage_operations.zig`, and `src/build/codegen_storage_layout.zig` |
| `src/build/gen_struct.zig` | `src/build/codegen_emit_struct.zig` and `src/build/codegen_emit_struct_fields.zig` |
| `src/build/gen_union.zig` | `src/build/codegen_union_layout.zig` |
| `src/build/gen_union_emit.zig` | `src/build/codegen_emit_union.zig` |
| `src/build/gen_wasi.zig` | `src/build/codegen_wasi_registry.zig` |
| `src/build/gen_wasi_emit.zig` | `src/build/codegen_emit_wasi.zig` |
| `src/build/gen_import.zig` | `src/build/codegen_imports.zig` |
| `src/build/gen_host.zig` | `src/build/codegen_host_imports.zig` |
| `src/build/gen_hooks.zig` | `src/build/codegen_callbacks.zig` |
| `src/build/gen_payload_wat.zig` | `src/build/wat_payload.zig` |
| `src/build/gen_storage_wat.zig` | `src/build/wat_storage.zig` |
| `src/build/gen_tuple.zig` | `src/build/codegen_emit_tuple.zig` |
| `src/build/gen_generic.zig` | `src/build/codegen_generics.zig` |
| `src/build/gen_ownership.zig` | `src/build/codegen_ownership.zig` |
| `src/build/backend_ir.zig` | `src/build/codegen_ir.zig` |
| `src/build/component_metadata_wat.zig` | `src/build/wat_component_metadata.zig` |
| `src/build/function_body_wat.zig` | `src/build/wat_function_body.zig` |
| `src/build/sema_scan.zig` | `src/build/sema_tokens.zig` |
| `src/build/sema_types.zig` | `src/build/sema_shapes.zig` |
| `src/build/sema_func_sig.zig` | `src/build/sema_function_signatures.zig` |
| `src/build/sema_func_call.zig` | `src/build/sema_function_calls.zig` |
| `src/build/sema_func_lambda.zig` | `src/build/sema_function_lambdas.zig` |
| `src/build/sema_func_shared.zig` | `src/build/sema_function_support.zig` |
| `src/build/sema_struct.zig` | `src/build/sema_structures.zig` |
| `src/build/sema_type.zig` | `src/build/sema_type_checks.zig` |
| `src/build/sema_import.zig` | `src/build/sema_imports.zig` |
| `src/build/sema_ctrl.zig` | `src/build/sema_control.zig` |
| `src/build/sema_util.zig` | deleted facade; direct imports from owning sema modules |

## Task 1: Capture Baseline and Add Boundary Guard

**Files:**
- Create: `src/build/test/check_module_boundaries.sh`
- Modify: `src/build/test/run_tests.sh` only to invoke the guard after the renamed modules exist
- Read: `src/build/*.zig`, `src/build/test/run_tests.sh`

**Interfaces:**
- The guard is an executable Bash script with no arguments.
- It exits `0` when the target file names and import directions are valid, otherwise exits nonzero and prints the offending path/import.
- It must check that no `gen_*.zig` or `sema_func_*.zig` compatibility files remain, no `gen_collect.zig` or `sema_util.zig` facade remains, collect files do not import `codegen_emit_*.zig`, and WAT fragment files do not import `codegen_pipeline.zig`.

- [ ] **Step 1: Record the baseline without editing source.**

```bash
find src/build -maxdepth 1 -type f -name '*.zig' | sort
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
git diff --check
```

Expected baseline: `117/117` Zig tests and `pass=941 fail=0 skip=3` from the regression harness, with only the already-present worktree changes.

- [ ] **Step 2: Write the guard with exact checks.**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_DIR="$ROOT/src/build"
fail=0

if find "$BUILD_DIR" -maxdepth 1 -type f \( -name 'gen_*.zig' -o -name 'sema_func_*.zig' \) -print -quit | grep -q .; then
    echo "old compiler module name remains" >&2
    fail=1
fi

for facade in "$BUILD_DIR/gen_collect.zig" "$BUILD_DIR/sema_util.zig"; do
    if [[ -e "$facade" ]]; then
        echo "facade remains: $facade" >&2
        fail=1
    fi
done

if rg -n '@import\("codegen_emit_[^"]+\.zig"\)' "$BUILD_DIR"/codegen_collect_*.zig "$BUILD_DIR"/codegen_collect_body.zig 2>/dev/null; then
    echo "collect module imports an emitter" >&2
    fail=1
fi

if rg -n '@import\("codegen_pipeline\.zig"\)' "$BUILD_DIR"/wat_*.zig "$BUILD_DIR"/runtime_* 2>/dev/null; then
    echo "WAT fragment imports codegen pipeline" >&2
    fail=1
fi

exit "$fail"
```

- [ ] **Step 3: Keep the invocation disabled until Task 9.** Do not make the guard fail the existing branch before the renamed files exist; add the invocation in the final guard task.

## Task 2: Rename Leaf Modules and Split Generic Helpers

**Files:**
- Rename: `gen_payload_wat.zig` -> `wat_payload.zig`
- Rename: `gen_storage_wat.zig` -> `wat_storage.zig`
- Rename: `gen_union.zig` -> `codegen_union_layout.zig`
- Rename: `gen_wasi.zig` -> `codegen_wasi_registry.zig`
- Split: `gen_util.zig` -> `codegen_tokens.zig` and `codegen_names.zig`
- Modify: every `src/build/*.zig` import and alias that references these files

**Interfaces:**
- `codegen_tokens.zig` owns token comparison, range, matching, line, and top-level scan helpers.
- `codegen_names.zig` owns public-name normalization, mangling, import-symbol formatting, and compiler-generated local names.
- `wat_payload.zig` and `wat_storage.zig` expose only WAT fragment emitters and layout constants.
- `codegen_union_layout.zig` owns `UnionLayout`, `UnionBranch`, layout equality, cloning, freeing, and branch-shape queries.
- `codegen_wasi_registry.zig` owns `WasiHostImport`, WIT signature tables, target lookup, and registry parsing. It does not emit WAT.

- [ ] **Step 1: Move files with `git mv` and update imports mechanically.** Preserve file contents during the move.
- [ ] **Step 2: Split `gen_util.zig` by function responsibility.** Move every token/range helper to `codegen_tokens.zig` and every name/mangle helper to `codegen_names.zig`; update aliases so no caller imports a generic helper facade.
- [ ] **Step 3: Rename moved public functions to snake_case while preserving parameters and return types.** For example, `tokEq` becomes `tok_eq`, `findMatching` becomes `find_matching`, `publicDeclName` becomes `public_decl_name`, and `appendWasiImportSymbol` becomes `append_wasi_import_symbol`.
- [ ] **Step 4: Run focused compile and full regression.**

```bash
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
git diff --check
```

- [ ] **Step 5: Stage only the leaf-module paths listed in this task.** Use `git add -p` for any call-site file that also contains pre-existing changes; verify the staged name list and diff before committing.

```bash
git diff --cached --check
git diff --cached --name-only
git commit -m "refactor: name codegen leaf modules by responsibility"
```

## Task 3: Split Shared Codegen Model, Context, and Constants

**Files:**
- Rename/split: `src/build/gen_types.zig` -> `src/build/codegen_model.zig`, `src/build/codegen_context.zig`, `src/build/codegen_constants.zig`
- Modify: all codegen imports of `gen_types.zig`
- Test: `src/main.zig` through `zig test`

**Interfaces:**
- `codegen_model.zig` owns declaration and shape data: `SourceOrigin`, `Local`, `StructDecl`, `StructField`, enum declarations, union locals, callback shapes, result shapes, import references, and other immutable records.
- `codegen_context.zig` owns `LocalSet`, `CodegenContext`, `StringDataContext`, loop/defer context, and mutable collection helpers.
- `codegen_constants.zig` owns temporary-local names and ABI/layout constants that have no behavior.
- `CodegenError` and `EmitOptions` are exposed from `codegen_model.zig` unless the actual call graph proves they belong to the API module.

- [ ] **Step 1: Move declarations without changing definitions.** Keep each type's fields, defaults, ownership, and deinit behavior byte-for-byte equivalent.
- [ ] **Step 2: Move `LocalSet` and context-dependent helpers to `codegen_context.zig`.** Update all call sites to import the context module directly.
- [ ] **Step 3: Move constants to `codegen_constants.zig`.** Replace broad `gen_types` aliases with exact module imports.
- [ ] **Step 4: Delete duplicate re-exports only after `rg 'gen_types|codegen_model|codegen_context|codegen_constants' src/build` shows every caller has a direct owner.**
- [ ] **Step 5: Verify ownership-sensitive code.**

```bash
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
git diff --check
```

- [ ] **Step 6: Stage only the model/context paths and their refactor hunks, then commit.** Do not stage unrelated existing changes in overlapping codegen files.

```bash
git diff --cached --check
git diff --cached --name-only
git commit -m "refactor: separate codegen model context and constants"
```

## Task 4: Rename and Flatten Semantic Analysis Modules

**Files:**
- Rename: `sema_scan.zig` -> `sema_tokens.zig`
- Rename: `sema_types.zig` -> `sema_shapes.zig`
- Rename: `sema_func_sig.zig` -> `sema_function_signatures.zig`
- Rename: `sema_func_call.zig` -> `sema_function_calls.zig`
- Rename: `sema_func_lambda.zig` -> `sema_function_lambdas.zig`
- Rename: `sema_func_shared.zig` -> `sema_function_support.zig`
- Rename: `sema_struct.zig` -> `sema_structures.zig`
- Rename: `sema_type.zig` -> `sema_type_checks.zig`
- Rename: `sema_import.zig` -> `sema_imports.zig`
- Rename: `sema_ctrl.zig` -> `sema_control.zig`
- Delete: `sema_func.zig`, `sema_util.zig` after direct-import migration
- Modify: `sema.zig`, `diagnostics.zig`, and every sema import site

**Interfaces:**
- `sema.zig` remains the public semantic entry point with `check_program` and `take_last_error_site`.
- `sema_shapes.zig` owns shared semantic records such as `FuncShape`, `CallArgShape`, `StructInfo`, and `ReturnArityResolve`.
- `sema_tokens.zig` owns token predicates and range scanning only.
- Function-domain modules own their domain and no longer require `sema_func.zig` or `sema_util.zig` re-exports.

- [ ] **Step 1: Rename semantic files without changing function bodies.**
- [ ] **Step 2: Convert the public semantic entry names and all internal sema functions to snake_case.** Examples: `checkProgram` -> `check_program`, `findMatching` -> `find_matching`, `callArityCompatibleWithFunc` -> `call_arity_compatible_with_func`.
- [ ] **Step 3: Replace facade imports with direct imports from `sema_tokens`, `sema_shapes`, and the owning function/type/control module.**
- [ ] **Step 4: Remove `sema_func.zig` and `sema_util.zig` only after no import or symbol alias references them.**
- [ ] **Step 5: Run the semantic-focused and full verification commands.**

```bash
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
git diff --check
```

- [ ] **Step 6: Stage only the semantic module paths and their refactor hunks, then commit.**

```bash
git diff --cached --check
git diff --cached --name-only
git commit -m "refactor: name semantic modules by domain"
```

## Task 5: Flatten Codegen Collection Modules

**Files:**
- Rename: `gen_collect_func.zig` -> `codegen_collect_functions.zig`
- Rename: `gen_collect_struct.zig` -> `codegen_collect_structs.zig`
- Rename: `gen_collect_type.zig` -> `codegen_collect_declarations.zig`
- Rename: `gen_expr_collect.zig` -> `codegen_collect_body.zig`
- Delete: `gen_collect.zig` after direct-import migration
- Modify: `gen_lower.zig`, `gen_expr.zig`, `gen_generic.zig`, `gen_storage.zig`, `gen_struct.zig`, and all collection import sites

**Interfaces:**
- `codegen_collect_functions.zig` owns function declarations, callback shapes, and function-level call collection.
- `codegen_collect_structs.zig` owns struct declarations, field layouts, and struct-local collection.
- `codegen_collect_declarations.zig` owns enum/value-enum/union declaration parsing and type binding.
- `codegen_collect_body.zig` owns body local collection, loop locals, multi-result locals, and temporary-local requirements.
- Collection modules may import `codegen_model`, `codegen_context`, parser/token helpers, import resolution, and pure layout modules. They must not import `codegen_emit_*`.

- [ ] **Step 1: Rename files and update imports without moving logic.**
- [ ] **Step 2: Move each symbol currently re-exported by `gen_collect.zig` to its direct owner and update callers.**
- [ ] **Step 3: Rename collection functions to `collect_*`, `parse_*`, `find_*`, and `is_*` according to side effects.
- [ ] **Step 4: Delete `gen_collect.zig` and run the boundary grep.**

```bash
if rg -n 'gen_collect\.zig|@import\("codegen_emit_[^"]+\.zig"\)' src/build/codegen_collect_*.zig src/build/codegen_collect_body.zig; then exit 1; fi
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
git diff --check
```

- [ ] **Step 5: Stage only the collect-layer paths and their refactor hunks, then commit.**

```bash
git diff --cached --check
git diff --cached --name-only
git commit -m "refactor: flatten codegen collection modules"
```

## Task 6: Split and Rename Codegen Emit Domains

**Files:**
- Rename: `gen_expr.zig` -> `codegen_emit_expression.zig` and `codegen_emit_call.zig`
- Rename: `gen_ctrl.zig` -> `codegen_emit_control.zig`
- Rename/split: `gen_storage.zig` -> `codegen_emit_storage_values.zig`, `codegen_emit_storage_operations.zig`, and `codegen_storage_layout.zig`
- Rename/split: `gen_struct.zig` -> `codegen_emit_struct.zig` and `codegen_emit_struct_fields.zig`
- Rename: `gen_union_emit.zig` -> `codegen_emit_union.zig`
- Rename: `gen_wasi_emit.zig` -> `codegen_emit_wasi.zig`
- Rename: `gen_tuple.zig` -> `codegen_emit_tuple.zig`
- Rename: `gen_hooks.zig` -> `codegen_callbacks.zig`
- Modify: all codegen imports and callback installation sites

**Interfaces:**
- `codegen_emit_expression.zig` dispatches expression kinds and delegates calls/control/storage/struct/union domains.
- `codegen_emit_call.zig` owns call-head resolution and call argument/result emission.
- `codegen_emit_control.zig` owns if/loop/defer/guard WAT.
- `codegen_emit_storage_values.zig` owns storage literals, bindings, and value construction.
- `codegen_emit_storage_operations.zig` owns storage set/put/copy/alias operations and their WAT emission.
- `codegen_storage_layout.zig` owns storage type parsing, element widths, and layout queries without WAT output.
- `codegen_emit_struct.zig` owns struct construction and aggregate emission; `codegen_emit_struct_fields.zig` owns field access, field metadata, and reflection emission.
- `codegen_emit_union.zig`, `codegen_emit_tuple.zig`, and `codegen_emit_wasi.zig` own only their corresponding WAT emission.
- `codegen_callbacks.zig` exposes callback types and installation points but no codegen domain logic.

- [ ] **Step 1: Use the current function list and import aliases to group each large file by responsibility before moving code.** The grouping record must name every moved function and its new owner; do not split by arbitrary line ranges.
- [ ] **Step 2: Move expression call emission out of the expression dispatcher.** Preserve the existing `EmitExprFn` contract until all callers compile; only change its name and module owner after the split is complete.
- [ ] **Step 3: Move storage operations and layout helpers into focused files.** Keep storage payload offsets, ownership actions, and WAT fragments identical.
- [ ] **Step 4: Move struct field reflection and union/WASI callback boundaries into their owning modules.** Keep `codegen_callbacks` free of domain implementation.
- [ ] **Step 5: Rename all moved functions to snake_case and replace `gen_*` aliases with direct imports.**
- [ ] **Step 6: Compile and run the complete fixture suite after each domain split.**

```bash
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
git diff --check
```

- [ ] **Step 7: Commit each coherent emit-domain split separately.** Use `refactor: split expression and call codegen` for the expression/call split and `refactor: isolate storage codegen responsibilities` for the storage split; do not combine unrelated domains in one commit.

Stage only the paths and hunks for the domain being committed. For overlapping files, use `git add -p`, then verify `git diff --cached --name-only` and `git diff --cached --check` before each commit.

## Task 7: Rename Pipeline, Runtime, Import, Generic, and Ownership Modules

**Files:**
- Rename: `gen_lower.zig` -> `codegen_pipeline.zig`
- Rename: `gen.zig` -> `codegen_api.zig`
- Rename: `gen_import.zig` -> `codegen_imports.zig`
- Rename: `gen_host.zig` -> `codegen_host_imports.zig`
- Rename: `gen_generic.zig` -> `codegen_generics.zig`
- Rename: `gen_ownership.zig` -> `codegen_ownership.zig`
- Rename: `backend_ir.zig` -> `codegen_ir.zig`
- Rename: `component_metadata_wat.zig` -> `wat_component_metadata.zig`
- Rename: `function_body_wat.zig` -> `wat_function_body.zig`
- Modify: `src/build/entry.zig`, `src/build/cli.zig`, and all imports of the renamed API/pipeline modules

**Interfaces:**
- `codegen_api.zig` exposes `emit_wat`, `emit_wat_with_options`, and `emit_test_wat`.
- `codegen_pipeline.zig` owns orchestration and is the only high-level codegen module that assembles collection and emission phases.
- `codegen_imports.zig` resolves module reachability and import references; `codegen_host_imports.zig` parses host locator/member/signature imports.
- `codegen_generics.zig`, `codegen_ownership.zig`, and `codegen_ir.zig` expose domain-specific helpers without re-exporting unrelated codegen functions.
- `wat_*` modules do not import `codegen_pipeline.zig`.

- [ ] **Step 1: Rename and update the pipeline/API imports.** Keep public entry behavior and `EmitOptions` fields unchanged.
- [ ] **Step 2: Rename pipeline and backend functions to snake_case.** Update `entry.zig`, `cli.zig`, and tests to use the new API names.
- [ ] **Step 3: Move WAT-only helpers into `wat_*` modules and verify their imports remain leaf-like.**
- [ ] **Step 4: Run the full verification commands and commit.**

```bash
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
git diff --check
git diff --cached --check
```

Stage only the paths listed in this task, using `git add -p` for overlapping files, then run the commit command.

## Task 8: Complete the Snake Case Sweep

**Files:**
- Modify: all Zig files under `src/build` that still contain camelCase internal functions or old `gen_*` symbol aliases
- Test: all existing Zig and integration tests

**Interfaces:**
- No public `.do` or WIT interface changes.
- All internal compiler call sites use snake_case function names.
- Type names remain PascalCase and constants remain UPPER_SNAKE_CASE.

- [ ] **Step 1: Find remaining violations.**

```bash
rg -n '^(pub )?fn [A-Za-z0-9]*[A-Z][A-Za-z0-9]*\(' src/build/*.zig
rg -n 'gen_(types|util|collect|expr|ctrl|struct|union|wasi|import|host|lower|generic|ownership|hooks)' src/build/*.zig
```

- [ ] **Step 2: Rename each remaining function at its definition and every call site.** Preserve the function signature types and implementation body; do not combine this sweep with behavior changes.
- [ ] **Step 3: Run the complete verification commands.**
- [ ] **Step 4: Commit the naming sweep.**

```bash
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
git diff --check
git diff --cached --check
```

Stage only the remaining naming-sweep hunks before the commit; do not stage existing socket or user changes.

## Task 9: Enable Structural Guard and Update Architecture Documentation

**Files:**
- Modify: `src/build/test/run_tests.sh`
- Modify: `AGENTS.md` only for the new module map, preserving unrelated user changes
- Modify: `docs/superpowers/specs/2026-07-15-codegen-structure-naming-design.md` only if implementation names differ from the approved target
- Test: `src/build/test/check_module_boundaries.sh`

**Interfaces:**
- `run_tests.sh` invokes the boundary guard after compiler build and before fixture execution.
- The guard is deterministic and reports the exact forbidden path or import.
- `AGENTS.md` lists only modules that exist after migration and states the one-way dependency rules.

- [ ] **Step 1: Add the guard invocation to `run_tests.sh` using the existing `$ROOT`/`$TEST_DIR` conventions.**
- [ ] **Step 2: Update the module map in `AGENTS.md` without changing user-authored unrelated sections.**
- [ ] **Step 3: Run the guard and full suite.**

```bash
src/build/test/check_module_boundaries.sh
(cd src && zig test main.zig)
./src/build/test/run_tests.sh
git diff --check
```

- [ ] **Step 4: Commit only the guard and architecture documentation.**

```bash
git add -p -- src/build/test/check_module_boundaries.sh src/build/test/run_tests.sh AGENTS.md
git diff --cached --check
git commit -m "test: enforce compiler module boundaries"
```

## Task 10: Final Verification and Handoff

**Files:**
- Read: all modified `src/build` files, the design document, and the implementation plan
- Test: compiler unit tests, full regression, socket ABI, and WAT validation

**Interfaces:**
- The public compiler command and `.do` behavior remain unchanged.
- The final report identifies verified results, skipped checks, and any residual naming debt.

- [ ] **Step 1: Run the compiler unit tests and full regression.**

```bash
cd src && zig test main.zig
cd .. && ./src/build/test/run_tests.sh
```

- [ ] **Step 2: Rebuild and validate the four socket fixtures.**

```bash
for f in 291_wasi_tcp_create_union 292_wasi_tcp_bind_payload_addr 296_wasi_tcp_bind_ipv6_payload_addr 297_wasi_tcp_create_dynamic_family; do
    ./bin/do build "src/build/test/compile_ok/${f}.do" -o "/tmp/${f}.wat"
    wasm-tools parse "/tmp/${f}.wat" -o "/tmp/${f}.wasm"
    wasm-tools validate "/tmp/${f}.wasm"
done
```

- [ ] **Step 3: Run the socket ABI assertion and structural guard.**

```bash
node src/build/test/test_socket_abi.mjs /tmp/291_wasi_tcp_create_union.wat /tmp/292_wasi_tcp_bind_payload_addr.wat /tmp/296_wasi_tcp_bind_ipv6_payload_addr.wat /tmp/297_wasi_tcp_create_dynamic_family.wat
src/build/test/check_module_boundaries.sh
git diff --check
```

- [ ] **Step 4: Confirm no unrelated files are staged or committed.** The final status must still show the pre-existing user files separately from the refactor files.
- [ ] **Step 5: Record the exact test counts and any intentionally skipped checks in the handoff.**
