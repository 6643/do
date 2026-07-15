# Repository Guidelines

## Project Structure & Module Organization

This repository contains the `do` language compiler and its regression suite.

- `lib/`: Standard library and builtin/core declaration table (`lib/_.do`). Bare `@lib("file.do")` resolves under this directory.
- `src/`: Toolchain and compiler sources (formerly `tool/`).
- `src/build/`: Zig compiler and `do build` source, kept as flat single-purpose modules.
    - Core pipeline: `src/build/lexer.zig` → `src/build/parser.zig` → `src/build/sema.zig` → `src/build/gen.zig`.
    - Shared pure helpers: `src/build/type_name.zig` (type/layout SSOT), `src/build/sema_error.zig`, `src/build/diagnostics.zig`.
    - Sema domain (flat modules; one-way deps; leaf domains do not import each other):
        - `sema.zig` — public entry (`checkProgram` / `takeLastErrorSite` / `ErrorSite`) + orchestration
        - `sema_util.zig` — facade re-exporting scan helpers + remaining shape helpers
        - `sema_scan.zig` — token/name/scan predicates (`tokEq`, `findMatching`, decl-start, naming)
        - `sema_types.zig` — shared shape types (`FuncShape` / `CallArgShape` / `StructInfo` / …)
        - `sema_func.zig` — func facade (sig / call / lambda re-exports)
        - `sema_func_sig.zig` / `sema_func_call.zig` / `sema_func_lambda.zig` / `sema_func_shared.zig` — signature, call/generic, lambda, shared helpers
        - `sema_struct.zig` — struct field/ctor, path segments, Tuple ctor/get
        - `sema_type.zig` — type decl naming/conflicts, enum/error/payload, union branches, type refs
        - `sema_import.zig` — host/local import + known WASI signature validation
        - `sema_ctrl.zig` — loop/label, defer, field reflection, assignment, constraint layout
    - Gen domain (flat modules; one-way deps; leaf domains do not import `gen_lower`):
        - `gen.zig` — public entry (`emitWat` / `emitTestWat`) + unit tests
        - `gen_lower.zig` — orchestration (`emitWat*` / hooks install) + minimal re-exports for tests
        - `gen_generic.zig` — generic func instantiate / type bind / prebind callback (no import of gen_lower)
        - `gen_hooks.zig` — late-bound emit callbacks (break reverse peer edges: ctrl/union→expr, struct→union_emit)
        - `gen_types.zig` — LocalSet, CodegenContext, decl types, free helpers, `ExprCallHead`
        - `gen_collect.zig` — collect facade (re-exports util/struct/func/type leaves)
        - `gen_collect_util.zig` / `gen_collect_struct.zig` / `gen_collect_func.zig` / `gen_collect_type.zig` — type parse/bind, struct/layout collect, func collect, enum/value-enum collect
        - `gen_expr.zig` — expression / call dispatch + re-exports body-local collect API
        - `gen_expr_collect.zig` — body-local / loop / multi-result local collection (no import of gen_expr)
        - `gen_ctrl.zig` — control-flow emit (`emitBody` / if / loop / defer / guard); uses hooks for expr/call
        - `gen_storage.zig` — storage emit (binding/put/set/agg) + re-exports tuple pack API
        - `gen_tuple.zig` — Tuple / pure-scalar pack helpers (load/store/inc/dec leaves; no import of gen_storage)
        - `gen_struct.zig` — struct binding / field / literal emit; uses hooks for union payload
        - `gen_union_emit.zig` — union value / binding emit; uses hooks for user-func call
        - `gen_wasi_emit.zig` — WASI host call/result emit (uses `EmitExprFn` / hooks; no import of `gen_lower`)
        - `gen_ownership.zig` — ARC release-plan emit and related scope helpers
        - `codegen_tokens.zig` — token/range/scan/decode helpers
        - `codegen_names.zig` — public names, core-func name tables, mangled symbols
        - `gen_host.zig` — unified `@host("env", member, sig)` host import collect/parse
        - `gen_import.zig` — module import resolve, reachability, string-data collect
        - `gen_wasi.zig` / `gen_union.zig` — WASI tables/parse, union layout
        - `gen_payload_wat.zig` / `gen_storage_wat.zig` — pure WAT fragments
        - `runtime_arc_wat.zig` — ARC runtime WAT + layout types SSOT (`ManagedFieldOffset` / `StructLayout` / `StringData`)
        - `runtime_prelude_wat.zig` — string-data memory emit + re-exports ARC API
        - plus `function_body_wat.zig` / `component_metadata_wat.zig` / `backend_ir.zig`
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
