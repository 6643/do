# Repository Guidelines

## Project Structure & Module Organization

This repository contains the `do` language compiler and its regression suite.

- `lib/`: Standard library and builtin/core declaration table (`lib/_.do`). Bare `@lib("file.do")` resolves under this directory.
- `src/`: Toolchain and compiler sources (formerly `tool/`).
- `src/build/`: Zig compiler and `do build` source, kept as flat single-purpose modules.
  - Core pipeline: `src/build/lexer.zig` → `src/build/parser.zig` → `src/build/sema.zig` → `src/build/codegen.zig`.
  - Shared pure helpers: `src/build/type_name.zig` (type/layout SSOT), `src/build/sema_error.zig`, `src/build/diagnostics.zig`.
  - Codegen domain WAT: `src/build/codegen_payload_wat.zig` (scalar/Tuple pack), `src/build/codegen_storage_wat.zig` (storage ptr/header), plus `src/build/function_body_wat.zig` / `src/build/runtime_prelude_wat.zig` / `src/build/component_metadata_wat.zig` / `src/build/backend_ir.zig` (scalar start 旁路, 非主路径).
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
