# Core Result Design

## Goal

Use ordinary Do unions as the source representation of WIT results when the
success and error payload types are distinct. Keep the compiler's tagged
result model for lossless WIT/ABI lowering, including private compatibility
probes whose two payload types are identical.

## Source Surface

Ordinary Do code writes `T | E` for distinct result arms. The existing
intrinsic `Result<T, E>` spelling remains accepted only as a compatibility
shape for registered private probes and same-type ABI cases; it is not the
recommended public Do API.

```do
parse_flag(input text) -> bool | ParseError {
    if input == "off" return false
    return InvalidFlag
}

open_file(path text) -> File | FileError {
    return host_file_open_at(path)
}
```

`@is(value, Type)` narrows an ordinary union by its payload type. Unit-success
results use `nil | E` and test the `nil` branch with `@eq(value, nil)`.

## Type And Narrowing Semantics

The compiler represents every WIT result internally as a two-case tagged
value: `Ok(T)` or `Err(E)`. This is an ABI model, not the normal source
spelling.

For source unions, `@is(value, T)` or `@is(value, E)` performs the narrowing.
The `Ok`/`Err` constructors and selectors remain only for the compatibility
`Result` shape; no `is_ok`, `is_err`, `ok`, `err`, or panic-style `unwrap` API is
introduced.

## WIT Boundary

The manifest and component lowering map WIT `result<T, E>` to an internal
tagged result. A declared source union such as `File | FileError` is checked
against the pinned WIT `Ok` and `Err` arms and lowers to that same tag. The tag
is preserved even when the two WIT payload types are identical; those cases
remain private compatibility shapes because ordinary Do unions reject duplicate
branches.

Examples:

| WIT | do |
| --- | --- |
| `result<list<u8>, error-code>` | `[u8] | FileError` |
| `result<descriptor, error-code>` | `File | FileError` |
| `result<_, error-code>` | `nil | FileError` |

Host imports should use `T | E` when the two source payload types differ. The
compiler verifies both arms against the pinned WIT result shape instead of
guessing from payload values. `Result<T, E>` remains available only for the
registered private/same-type compatibility cases.

## Constraints

- Ordinary unions retain unique branch types; `T | T` is invalid.
- The compatibility `Result` shape takes exactly two type arguments and keeps
  the existing contextual `Ok`/`Err` construction rules.
- Result payload ownership follows the payload types' existing move/ARC rules;
  the internal tag introduces no references or borrow syntax.

## Non-Goals

- Do not add user-defined generic payload enums.
- Do not change source `Tuple`, `[T]`, `Future`, or `Stream` spelling.
- Prefer ordinary `T | E` unions for new user APIs and standard-library host
  declarations when `T` and `E` differ.
- Do not expose WIT `own<T>` or `borrow<T>` as ordinary do types.
