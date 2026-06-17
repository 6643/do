# do fmt 07.2 Design

## Goal

Define the first stable `do fmt` contract before implementation: command surface, formatting rules, fixture shape, and verification gates.

## Current Evidence

- `tool/fmt/` currently only contains `.gitkeep`; no formatter implementation exists.
- `tool/main.zig` currently dispatches `build`, `test`, and `run`; no `fmt` command exists.
- `tool/build/cli.zig` only parses `build`, `test`, and `run` arguments.
- `doc/roadmap_status.md` marks `07.2` as needing a formatting specification and stable output regression before implementation.

## Recommended Scope

First version should be a conservative source formatter, not a style optimizer.

It must:

- accept exactly one `.do` input file;
- emit formatted source to stdout by default;
- support `--check` to compare formatted output with the input and return non-zero on mismatch;
- not write files in the first implementation;
- preserve all semantic tokens exactly;
- preserve standalone line comments and block comments as comments;
- preserve line-string text after `\\` exactly except for indentation before the `\\`;
- normalize line endings to `\n`;
- ensure a final newline;
- remove trailing whitespace;
- use 4 spaces per indentation level;
- be idempotent: formatting already formatted output produces identical bytes.

It must not yet:

- reorder declarations or imports;
- wrap long lines by width;
- rewrite expressions for style;
- normalize string escapes;
- convert comments between line and block form;
- format multiple files in one command;
- modify files in place.

## Command Contract

```text
do fmt <input.do>
do fmt --check <input.do>
```

Rules:

- `do fmt <input.do>` prints formatted source to stdout and diagnostics to stderr.
- `do fmt --check <input.do>` prints nothing on success.
- If `--check` finds a mismatch, it exits non-zero and prints `error[FormatMismatch]: input is not formatted`.
- Extra positional arguments, unknown flags, or missing input path use the existing CLI diagnostic style.
- Parse or lex errors use the existing compile diagnostic style and do not emit partial formatted output.

## Formatting Rules

### Files

- Output uses LF line endings.
- Output always ends with exactly one trailing newline.
- Blank lines have no spaces.
- Trailing whitespace is removed from every line.
- Tabs in indentation are rewritten as spaces according to the computed indentation level.

### Indentation

- Indentation unit is 4 spaces.
- Lines whose first token is `}` are indented one level less than the current block.
- Lines after a `{` increase indentation by one level.
- Lines containing only comments use the indentation level of the next real token when possible; otherwise they use the current block level.
- Line strings keep their payload bytes after `\\` unchanged, but their leading indentation before `\\` is normalized to the current block level.

### Spacing

- One space after commas in parameter, argument, generic argument, return, and aggregate lists when they stay on one line.
- No space immediately inside `(`, `)`, `<`, `>`, `{`, `}`.
- One space around `=`, `->`, `=>`, and binary operator-like core calls are not rewritten because they are ordinary calls.
- Field path segments keep `.field` with no added space after `.`.
- Builtin calls keep `@name(...)` with no space between name and `(`.
- Spread keeps `...rest` with no added space inside the spread token.

### Line Breaking

First version preserves existing statement and expression line breaks. It does not choose new wrapping by width.

It may normalize obvious block structure:

```do
User {
    id i32
    name text
}

add_one(x i32) -> i32 {
    return @add(x, 1)
}
```

It does not collapse multi-line calls or aggregates:

```do
value = User{
    id = 1,
    name = "Ada",
}
```

## Implementation Architecture

Use a dedicated formatter module under `tool/fmt/` rather than folding this into build or run.

Suggested files:

- `tool/fmt/run.zig`: CLI orchestration, file I/O, stdout/check behavior.
- `tool/fmt/format.zig`: pure formatter from source bytes to formatted bytes.
- `tool/build/cli.zig`: `parseFmt(args)` and `FmtArgs`.
- `tool/main.zig`: command dispatch and usage.
- `tool/build/test/fmt/`: input fixtures and `.expect` formatted output.
- `tool/build/test/run_tests.sh`: fmt fixture loop and CLI strict-args checks.

The formatter should initially use a small lossless scanner that preserves trivia. The existing compiler lexer intentionally discards whitespace and comments, so using it alone cannot preserve comments or line strings safely.

## Regression Contract

Each fixture under `tool/build/test/fmt/*.do` has a matching `.expect` file.

Harness checks:

1. `do fmt fixture.do` stdout equals `.expect`.
2. stderr is empty for valid fixtures.
3. formatting the `.expect` file output again is byte-identical.
4. `do fmt --check formatted.do` exits 0.
5. `do fmt --check unformatted.do` exits non-zero and contains `error[FormatMismatch]`.
6. CLI strict-args covers unknown flag, extra input, missing input.

Initial fixtures:

- top-level struct and function indentation;
- comments and blank lines;
- line strings;
- generic function and type args;
- aggregate literals;
- loop / if / defer block indentation.

## Open Boundaries

These stay out of the first implementation:

- width-based wrapping;
- preserving exact comment vertical attachment rules beyond standalone comments;
- in-place writes;
- formatting entire directories;
- AST-level expression rewriting.

## Self Review

- No placeholder sections remain.
- The first implementation has a narrow command surface and stable regression shape.
- The design avoids relying on the existing lexer for comment preservation, because the current lexer drops comments and whitespace.
- The testing contract proves idempotence and `--check`, not just one-shot formatting.
