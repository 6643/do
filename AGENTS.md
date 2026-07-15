# Repository Guidelines

## Project Structure & Module Organization

This repository contains the `do` language compiler and its regression suite.

- `lib/`: Standard library and builtin/core declaration table (`lib/_.do`). Bare `@lib("file.do")` resolves under this directory.
- `src/`: Toolchain and compiler sources (formerly `tool/`).
- `src/build/`: Zig compiler and `do build` source, kept as flat single-purpose modules.
    - Core pipeline: `src/build/lexer.zig` → `src/build/parser.zig` → `src/build/sema.zig` → `src/build/codegen_api.zig`.
    - Shared pure helpers: `src/build/type_name.zig` (type/layout SSOT), `src/build/sema_error.zig`, `src/build/diagnostics.zig`.
    - Sema domain (flat modules; one-way deps; leaf domains do not import each other):
        - `sema.zig` — public entry (`check_program` / `take_last_error_site` / `ErrorSite`) + orchestration
        - `sema_tokens.zig` — token/name/scan predicates and range helpers
        - `sema_shapes.zig` — shared shape types (`FuncShape` / `CallArgShape` / `StructInfo` / …)
        - `sema_function_signatures.zig` / `sema_function_calls.zig` / `sema_function_lambdas.zig` — function signatures, calls/generics, lambdas
        - `sema_function_support.zig` — shared semantic support helpers used by multiple sema domains
        - `sema_structures.zig` — struct field/ctor, path segments, Tuple ctor/get
        - `sema_type_checks.zig` — type decl naming/conflicts, enum/error/payload, union branches, type refs
        - `sema_imports.zig` — host/local import + known WASI signature validation
        - `sema_control.zig` — loop/label, defer, field reflection, assignment, constraint layout
    - Gen domain (flat modules; one-way deps; leaf domains do not import `codegen_pipeline`):
        - `codegen_api.zig` — public entry (`emit_wat` / `emit_test_wat`) + unit tests
        - `codegen_pipeline.zig` — orchestration (`emit_wat*` / hooks install) + minimal re-exports for tests
        - `codegen_generics.zig` — generic func instantiate / type bind / prebind callback (no import of codegen_pipeline)
        - `codegen_callbacks.zig` — late-bound emit callbacks (break reverse peer edges: control/union→expression, struct→union)
        - `codegen_model.zig` — immutable declarations, shape records, ownership/free helpers, `ExprCallHead`
        - `codegen_context.zig` — LocalSet, mutable codegen contexts, local-name helpers
        - `codegen_constants.zig` — ABI/layout IDs and compiler temporary-local names
        - `codegen_collect_util.zig` / `codegen_collect_structs.zig` / `codegen_collect_functions.zig` / `codegen_collect_declarations.zig` — type parse/bind, struct/layout collect, func collect, enum/value-enum collect
        - `codegen_emit_expression.zig` / `codegen_emit_call.zig` — expression / call dispatch
        - `codegen_body.zig` — body-local / loop / multi-result collection plus body orchestration; emitter dependencies are isolated behind this boundary
        - `codegen_collect_reflection.zig` — pure field-reflection and body-binding collection helpers
        - `codegen_emit_control.zig` — control-flow emit (`emit_body` / if / loop / defer / guard); uses hooks for expression/call
        - `codegen_emit_storage_operations.zig` / `codegen_emit_storage_values.zig` / `codegen_storage_layout.zig` — storage emit, layout, and Tuple pack API
        - `codegen_emit_tuple.zig` — Tuple / pure-scalar pack helpers (load/store/inc/dec leaves)
        - `codegen_emit_struct.zig` / `codegen_emit_struct_fields.zig` — struct binding / field / literal emit; uses hooks for union payload
        - `codegen_emit_union.zig` — union value / binding emit; uses hooks for user-func call
        - `codegen_emit_wasi.zig` — WASI host call/result emit (uses `EmitExprFn` / hooks; no import of `codegen_pipeline`)
        - `codegen_ownership.zig` — ARC release-plan emit and related scope helpers
        - `codegen_tokens.zig` — token/range/scan/decode helpers
        - `codegen_names.zig` — public names, core-func name tables, mangled symbols
        - `codegen_host_imports.zig` — unified `@host("env", member, sig)` host import collect/parse
        - `codegen_imports.zig` — module import resolve, reachability, string-data collect
        - `codegen_wasi_registry.zig` / `codegen_union_layout.zig` — WASI tables/parse, union layout
        - `gen_payload_wat.zig` / `gen_storage_wat.zig` — pure WAT fragments
        - `runtime_arc_wat.zig` — ARC runtime WAT + layout types SSOT (`ManagedFieldOffset` / `StructLayout` / `StringData`)
        - `runtime_prelude_wat.zig` — string-data memory emit + re-exports ARC API
        - plus `wat_function_body.zig` / `wat_component_metadata.zig` / `codegen_ir.zig`
- `src/main.zig`: Single CLI dispatch entrypoint for the `bin/do` tool.
- `src/build.zig`: Zig build entrypoint. It installs the compiler binary to the repository `bin/` directory.
- `bin/do`: Built compiler executable.
- `doc/`: Language syntax, parser grammar, runtime, and memory design references, centered on `doc/spec.md` and `doc/grammar.peg`.
- `src/build/test/`: Current compiler and build-output regression tests and expected diagnostics.
- `doc/memory.md`: v1 runtime / ARC memory model (authoritative).

## Build, Test, and Development Commands

Run commands from the repository root unless noted.

```bash
cd src && zig build -Doptimize=ReleaseSmall
```

Builds the compiler and installs `bin/do`.

```bash
./bin/do build src/build/test/compile_ok/01_start_entry_valid.do -o /tmp/start.wat
./bin/do test src/build/test/ok/01_path_get_single.do
```

Compiles a regression fixture to WAT, or runs `test` declarations in a `.do` fixture.

```bash
./src/build/test/run_tests.sh
ZIG_BIN=/path/to/zig ./src/build/test/run_tests.sh
```

Builds the compiler in Debug mode, then runs all integration cases.

## Coding Style & Naming Conventions

Use Zig for compiler implementation and keep modules flat under `src/build/`. Prefer explicit data flow, small functions, and guard-style early returns. Keep side effects at command, file, or code generation boundaries. Use lowercase snake_case for Zig identifiers and descriptive file names that match the compiler phase.

For `.do` fixtures, use numbered names that describe the behavior, for example `14_dot_selector_batch_expr.do` or `01_missing_start_entry.do`.

## Testing Guidelines

Add behavior tests under `src/build/test/ok` for successful `do test` runs, and under `src/build/test/err` for expected `do test` failures. Add compile-mode tests under `compile_ok` or `compile_err`. Every failing case must include a matching `.expect` file with diagnostic substrings, one per line.

Run `./src/build/test/run_tests.sh` before handing off changes that touch syntax, parsing, semantic analysis, code generation, diagnostics, or CLI behavior.

## Commit & Pull Request Guidelines

Recent history uses short imperative or status-style subjects, including `Auto save: YYYY-MM-DD HH:MM:SS` and direct summaries such as `Update README for do language with version note`. Prefer concise subjects that name the changed area.

Pull requests should describe the compiler behavior changed, list updated test cases, and include the exact verification command and result. For parser syntax changes, update `doc/grammar.peg`; for semantic changes, update `doc/spec_rules.md` in the same change.
