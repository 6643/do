# Repository Guidelines

## Project Structure & Module Organization

This repository contains the `do` language compiler and its regression suite.

- `tool/build/`: Zig compiler and `do build` source, kept as flat single-purpose modules such as `lexer.zig`, `parser.zig`, `sema.zig`, and `codegen.zig`.
- `tool/main.zig`: Single CLI dispatch entrypoint for the `bin/do` tool.
- `tool/build.zig`: Zig build entrypoint. It installs the compiler binary to the repository `bin/` directory.
- `bin/do`: Built compiler executable.
- `doc/`: Language syntax, runtime, and memory design references, centered on `doc/spec.md`.
- `tool/build/test/`: Current compiler and build-output regression tests and expected diagnostics.
- `tool/test/`: Reserved implementation directory for the future `do test` command.
- `doc/rc.md` and `doc/gc.ts`: Runtime and memory design notes/prototypes.

## Build, Test, and Development Commands

Run commands from the repository root unless noted.

```bash
cd tool && zig build -Doptimize=ReleaseSmall
```

Builds the compiler and installs `bin/do`.

```bash
./bin/do build tool/build/test/cases/compile_ok/01_start_entry_valid.do -o /tmp/start.wat
./bin/do test tool/build/test/cases/ok/01_path_get_single.do
```

Compiles a regression fixture to WAT, or runs `test` declarations in a `.do` fixture.

```bash
./tool/build/test/run_tests.sh
ZIG_BIN=/path/to/zig ./tool/build/test/run_tests.sh
```

Builds the compiler in Debug mode, then runs all integration cases.

## Coding Style & Naming Conventions

Use Zig for compiler implementation and keep modules flat under `tool/build/`. Prefer explicit data flow, small functions, and guard-style early returns. Keep side effects at command, file, or code generation boundaries. Use lowercase snake_case for Zig identifiers and descriptive file names that match the compiler phase.

For `.do` fixtures, use numbered names that describe the behavior, for example `14_dot_selector_batch_expr.do` or `01_missing_start_entry.do`.

## Testing Guidelines

Add behavior tests under `tool/build/test/cases/ok` for successful `do test` runs, and under `tool/build/test/cases/err` for expected `do test` failures. Add compile-mode tests under `compile_ok` or `compile_err`. Every failing case must include a matching `.expect` file with diagnostic substrings, one per line.

Run `./tool/build/test/run_tests.sh` before handing off changes that touch syntax, parsing, semantic analysis, code generation, diagnostics, or CLI behavior.

## Commit & Pull Request Guidelines

Recent history uses short imperative or status-style subjects, including `Auto save: YYYY-MM-DD HH:MM:SS` and direct summaries such as `Update README for do language with version note`. Prefer concise subjects that name the changed area.

Pull requests should describe the compiler behavior changed, list updated test cases, and include the exact verification command and result. For syntax or semantic changes, update `doc/spec.md` in the same change.
