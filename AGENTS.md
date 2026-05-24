# Repository Guidelines

## Project Structure & Module Organization

This repository contains the `do` language compiler and its regression suite.

- `compiler/src/`: Zig compiler source, kept as flat single-purpose modules such as `lexer.zig`, `parser.zig`, `sema.zig`, and `codegen.zig`.
- `compiler/build.zig`: Zig build entrypoint. It installs the compiler binary to the repository `bin/` directory.
- `bin/do`: Built compiler executable.
- `doc/`: Language syntax and semantic references, centered on `doc/syntax.md`.
- `tests/do/`: Integration regression tests and expected diagnostics.
- `gc.md` and `gc.ts`: Runtime and GC design notes/prototypes.

## Build, Test, and Development Commands

Run commands from the repository root unless noted.

```bash
cd compiler && zig build -Doptimize=ReleaseSmall
```

Builds the compiler and installs `bin/do`.

```bash
./bin/do tests/do/cases/compile_ok/01_start_entry_valid.do -o /tmp/start.wat
./bin/do test tests/do/cases/ok/01_import_only.do
```

Compiles a regression fixture to WAT, or runs `test` declarations in a `.do` fixture.

```bash
./tests/do/run_tests.sh
ZIG_BIN=/path/to/zig ./tests/do/run_tests.sh
```

Builds the compiler in Debug mode, then runs all integration cases.

## Coding Style & Naming Conventions

Use Zig for compiler implementation and keep modules flat under `compiler/src/`. Prefer explicit data flow, small functions, and guard-style early returns. Keep side effects at command, file, or code generation boundaries. Use lowercase snake_case for Zig identifiers and descriptive file names that match the compiler phase.

For `.do` fixtures, use numbered names that describe the behavior, for example `14_dot_selector_batch_expr.do` or `01_missing_start_entry.do`.

## Testing Guidelines

Add behavior tests under `tests/do/cases/ok` for successful `do test` runs, and under `tests/do/cases/err` for expected `do test` failures. Add compile-mode tests under `compile_ok` or `compile_err`. Every failing case must include a matching `.expect` file with diagnostic substrings, one per line.

Run `./tests/do/run_tests.sh` before handing off changes that touch syntax, parsing, semantic analysis, code generation, diagnostics, or CLI behavior.

## Commit & Pull Request Guidelines

Recent history uses short imperative or status-style subjects, including `Auto save: YYYY-MM-DD HH:MM:SS` and direct summaries such as `Update README for do language with version note`. Prefer concise subjects that name the changed area.

Pull requests should describe the compiler behavior changed, list updated test cases, and include the exact verification command and result. For syntax or semantic changes, update `doc/syntax.md` in the same change.
