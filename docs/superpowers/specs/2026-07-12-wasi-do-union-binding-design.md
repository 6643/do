# Design: WASI host signatures as do types (`T | nil`, `Ok | Err`)

**Status:** Approved (session 2026-07-12)  
**Scope:** Declarative `@wasi_func` parameter/result surface; stdlib dir/file host lines; compiler validate + lower.

## Goal

Bind WASI host imports to **do types** in signatures (not WIT-only literals), using ordinary do unions for option/result shapes. No `@wasi_result` / `@wasi_option` / `@wasi_tuple` type wrappers.

## Decisions

| Topic | Decision |
|-------|----------|
| Option | `T \| nil` |
| Result (fallible) | `Ok \| Err` (exclusive; never multi-return `Ok, Err`) |
| Unit ok + fail | `nil \| i32` (not `result<_, error-code>` as the long-term do form) |
| Payload ok + fail | e.g. `Dir \| i32`, `u64 \| i32` |
| Infallible | single type or `nil` (`() -> Datetime`, `(Dir) -> nil`) |
| Err arm (phase 1) | `i32` = WASI **status** (0 never appears as err arm; ok only via Ok/`nil`) |
| Public API | still `Dir \| DirError` etc.; wrappers map status → coarse error |
| Resource params | `Dir` / `File` (`@wasi_resource`) → handle via `.id` |
| Record results | keep `Datetime` (`@wasi_record`) |
| Structures in params | do `Tuple<…>` / multi-arg flatten / `@wasi_record`; **no** `@wasi_tuple` |
| Type wrappers | **no** `wasi_result`, `wasi_option`, `wasi_list`, `wasi_tuple` |
| Keep `@wasi_*` | `wasi_func`, `wasi_resource`, `wasi_record`, optional later `wasi_enum` |
| Multi-return as result | **forbidden** as source model (no zero values; dual presence invalid) |
| Statement discard | whole `Ok\|Err` / `nil\|i32` value discardable (fixture 100 behavior) |
| Transition | existing `result<…>` / WIT sugar still accepted until stdlib+fixtures migrated |

## Mapping table (source → WIT manifest)

| do signature fragment | WIT (manifest) |
|----------------------|----------------|
| `Dir` / `File` | `descriptor` |
| `i32` (descriptor sugar) | `descriptor` (known targets) |
| `text` | `string` / `text` |
| `[u8]` | `list<u8>` |
| `Tuple<A,B>` | `tuple<A',B'>` |
| `nil \| i32` | `result<_, error-code>` (or stream-error analog) |
| `Dir \| i32` | `result<descriptor, error-code>` |
| `u64 \| i32` | `result<filesize, error-code>` etc. |
| `[u8] \| i32` | `result<list<u8>, …>` |
| `Datetime` | record path already known |
| `nil` | unit / no result |

Codegen continues result-area / status strategies internally; **source types** are unions, not multi-lhs ABI.

## Call model

```do
// Fallible with payload
r Dir | i32 = host_dir_open_at(parent, 0, path, 2, 0)
if @is(r, Dir) { /* use r */ } else { /* r is status i32 */ }

// Unit fallible + statement discard
host_file_sync(d)           // discard nil|i32
s nil | i32 = host_file_sync(d)

// Infallible
host_dir_drop(d)            // nil
t Datetime = host_now()
```

Public wrapper example:

```do
open_dir_at(parent Dir, path text) -> Dir | DirError {
    r Dir | i32 = host_dir_open_at(parent, 0, path, 2, 0)
    if @is(r, Dir) return r
    return DirOpenFailed
}
```

## Non-goals

- `@wasi_enum` productization / fine error-code enums (optional later)
- G6.2 read-directory stream/future
- G6.3 sockets variant
- Changing public stdlib API names (`open_dir_at`, `DirError`, …)
- Reintroducing bare `@wasi(...)`

## Phased delivery

1. **Compiler:** accept `Ok|Err` / `T|nil` / resource names in `@wasi_func` sigs; map to WIT; lower calls to union (or keep multi-lhs only as internal, not source-required).
2. **Known table:** extend `do_params` / `do_result` for union forms.
3. **Stdlib:** migrate `lib/dir.do`, `lib/file.do`, `lib/io.stream.do` host lines + thin wrappers.
4. **Fixtures:** migrate compile_ok wasi result cases; keep 100 statement semantics.
5. **Docs:** spec_rules §21/§23, wasi_p3_lowering, grammar notes.

## Success criteria

- Host lines can write `(Dir, …) -> Dir | i32` and `(Dir) -> nil | i32`.
- No requirement for multi-return result binding in new code.
- Regression `fail=0`; statement unit result still works.
- Stdlib public wrappers still return `Dir | DirError` / `File | FileError`.
