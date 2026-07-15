# Compiler Structure and Naming Refactor Design

## Scope

This refactor covers the compiler implementation under `src/build`.

It changes internal file boundaries, module names, and Zig function names. It does not change language semantics, parser grammar, WASI ABI, generated runtime behavior, standard-library interfaces, allocation strategy, or generated instruction strategy.

The current worktree is intentionally dirty. Existing changes in `AGENTS.md`, the socket ABI fix, standard-library wrappers, tests, `a.md`, and the async design note must be preserved. The refactor may update `src/build` and the structural guard/documentation needed to describe the new layout.

## Evidence

The current compiler has 57 top-level Zig modules under `src/build`. The largest modules are:

| File | Lines | Observed issue |
| --- | ---: | --- |
| `gen_storage.zig` | 3866 | Storage emission, storage inference, calls, and unrelated lookup helpers are mixed. |
| `gen_expr.zig` | 3256 | Expression dispatch, calls, local inference, and emission are mixed. |
| `gen_struct.zig` | 2626 | Struct emission is coupled to field reflection, inference, and cross-domain helpers. |
| `gen_ctrl.zig` | 2483 | Control-flow emission imports most other codegen domains. |
| `gen_wasi_emit.zig` | 2342 | WASI ABI lowering and generic codegen helper exports are mixed. |
| `gen_types.zig` | 1141 | Declaration models, local models, function shapes, context, constants, and cleanup helpers are mixed. |

Recent history shows repeated partial splits of `codegen_api.zig` into `gen_util`, `gen_wasi`, `gen_impl`, `codegen_pipeline`, `gen_collect`, and domain files. The names describe different dimensions at the same level: phase, domain, implementation detail, and generic utility. The result is a broad re-export graph and unclear ownership.

## Target Architecture

The target dependency direction is:

```text
entry / cli
    -> parser
    -> sema
    -> codegen_api
         -> codegen_pipeline
              -> collect
              -> model / context
              -> emit
                   -> wat fragments / runtime
```

The rules are:

1. `parser` owns tokens and syntax structures.
2. `sema` owns language validity, types, calls, imports, and control-flow checks. It does not import codegen modules.
3. `codegen_model` owns codegen data shapes and declaration models.
4. `codegen_context` owns local sets, codegen context state, and compilation-scoped mutable state.
5. `codegen_collect_*` performs scans, local collection, declaration collection, and layout preparation. It does not write WAT.
6. `codegen_emit_*` writes WAT for one domain. It does not perform whole-program collection.
7. `codegen_pipeline` owns stage orchestration and internal callback installation.
8. `codegen_api` exposes only stable codegen entry points such as `emit_wat` and `emit_test_wat`.
9. `codegen_callbacks` contains callback types and late-bound installation points only. It does not contain domain logic.
10. `wat_*` and `runtime_*_wat` modules emit pure WAT fragments and cannot depend on high-level codegen orchestration.

The refactor may retain callbacks where they are required to break a reverse dependency, but the callback contract must live in one module and its ownership must be explicit.

## File Naming

The directory remains flat. File names use lowercase snake case and describe one domain and one responsibility.

| Current file | Target role/name |
| --- | --- |
| `codegen_api.zig` | `codegen_api.zig` |
| `codegen_pipeline.zig` | `codegen_pipeline.zig` |
| `gen_types.zig` | `codegen_model.zig` plus `codegen_context.zig` and `codegen_constants.zig` |
| `gen_util.zig` | `codegen_tokens.zig` plus `codegen_names.zig` |
| `gen_collect_func.zig` | `codegen_collect_functions.zig` |
| `gen_collect_struct.zig` | `codegen_collect_structs.zig` |
| `gen_collect_type.zig` | `codegen_collect_declarations.zig` |
| `gen_collect.zig` | removed as a facade; call sites import the owning collect module directly |
| `gen_expr_collect.zig` | `codegen_collect_body.zig` |
| `gen_expr.zig` | `codegen_emit_expression.zig` plus `codegen_emit_call.zig` |
| `gen_ctrl.zig` | `codegen_emit_control.zig` |
| `gen_struct.zig` | `codegen_emit_struct.zig` |
| `gen_union.zig` | `codegen_union_layout.zig` |
| `gen_union_emit.zig` | `codegen_emit_union.zig` |
| `gen_wasi.zig` | `codegen_wasi_registry.zig` |
| `gen_wasi_emit.zig` | `codegen_emit_wasi.zig` |
| `codegen_imports.zig` | `codegen_imports.zig` |
| `codegen_host_imports.zig` | `codegen_host_imports.zig` |
| `gen_hooks.zig` | `codegen_callbacks.zig` |
| `gen_payload_wat.zig` | `wat_payload.zig` |
| `gen_storage_wat.zig` | `wat_storage.zig` |
| `gen_tuple.zig` | `codegen_emit_tuple.zig` |
| `codegen_generics.zig` | `codegen_generics.zig` |
| `codegen_ownership.zig` | `codegen_ownership.zig` |
| `codegen_ir.zig` | `codegen_ir.zig` |
| `wat_component_metadata.zig` | `wat_component_metadata.zig` |
| `wat_function_body.zig` | `wat_function_body.zig` |

Large domains are split by responsibility during migration. For example, storage code may become storage value emission, storage operations/calls, and storage layout helpers. The exact split is finalized from the actual function clusters during the implementation plan; no new module may be created only to move a random group of functions.

Semantic analysis follows the same naming principles:

| Current file | Target role/name |
| --- | --- |
| `sema_scan.zig` | `sema_tokens.zig` |
| `sema_types.zig` | `sema_shapes.zig` |
| `sema_func_sig.zig` | `sema_function_signatures.zig` |
| `sema_func_call.zig` | `sema_function_calls.zig` |
| `sema_func_lambda.zig` | `sema_function_lambdas.zig` |
| `sema_func_shared.zig` | `sema_function_support.zig` |
| `sema_struct.zig` | `sema_structures.zig` |
| `sema_type.zig` | `sema_type_checks.zig` |
| `sema_import.zig` | `sema_imports.zig` |
| `sema_ctrl.zig` | `sema_control.zig` |
| `sema_util.zig` | removed as a facade; direct imports replace re-exports |

## Function Naming

Internal Zig functions use lowercase snake case. Types use PascalCase. Constants use UPPER_SNAKE_CASE.

| Prefix | Contract |
| --- | --- |
| `emit_*` | Writes WAT or an output fragment. |
| `collect_*` | Mutates a collector or gathers pre-codegen facts. |
| `resolve_*` | Resolves a candidate, type, call, overload, or binding. |
| `parse_*` | Parses a token/range into a structured value. |
| `find_*` | Performs a side-effect-free lookup. |
| `is_*`, `has_*`, `can_*` | Performs a side-effect-free predicate check. |
| `append_*` | Appends bytes or a WAT instruction sequence to an output buffer. |
| `load_*`, `store_*` | Explicitly performs a generated memory load/store. |

Examples:

```text
emitWasiResultDescriptorCall -> emit_wasi_descriptor_call
findStructLayout             -> find_struct_layout
codegenTypesCompatible       -> codegen_types_compatible
appendStoreU64BigEndianField -> append_store_u64_big_endian_field
```

`get_*` is reserved for actual read/access semantics. It must not replace `find_*` or `resolve_*`. Generic names such as `gen_*`, `util_*`, `impl_*`, and `types_*` are not allowed for new functions or files.

## Migration Order

Each stage is a separate reviewable change and must compile before the next stage.

1. Capture the baseline module list, import graph, test counts, and generated WAT checks. Do not alter existing dirty files outside the approved scope.
2. Rename low-coupling leaf modules and their imports: token/name helpers, pure WAT fragments, union layout, and WASI registry.
3. Split `gen_types` into model, context, and constants; update direct imports and remove only redundant re-exports.
4. Split the collect layer into declarations, functions, structs, and body collection. Assert that collect modules do not import emit modules.
5. Split the emit layer into expression/call, control, storage, struct, union, tuple, and WASI domains. Keep callbacks in `codegen_callbacks`.
6. Rename all touched internal functions to snake case, then sweep the rest of `src/build` so the compiler implementation has one naming convention.
7. Add a module-boundary guard and update the repository architecture documentation. The guard checks old module paths, forbidden facade imports, and forbidden layer directions.

No stage changes `.do` semantics, WIT signatures, WAT ABI layout, ARC behavior, or code-generation instruction strategy.

## Verification

Every stage runs:

```bash
cd src && zig test main.zig
./src/build/test/run_tests.sh
git diff --check
```

The final stage additionally verifies:

- no old module paths remain under `src/build` or its import sites;
- the module-boundary guard passes;
- compile-ok, compile-err, runtime, socket ABI, and WAT parse/validate checks pass;
- the final test counts match the baseline except for explicitly documented test additions;
- no changes exist in language fixtures or standard-library behavior beyond already-present worktree changes.

Performance work is explicitly out of scope for this refactor. Repeated scans, layout lookup caching, allocation changes, and generated instruction changes are deferred to a separate evidence-driven project.

## Non-goals

- No parser or language syntax redesign.
- No semantic behavior changes.
- No WASI ABI or runtime changes.
- No standard-library API changes.
- No compiler performance optimization.
- No directory hierarchy under `src/build`.
- No compatibility facade retained only to hide an unclear ownership boundary.
