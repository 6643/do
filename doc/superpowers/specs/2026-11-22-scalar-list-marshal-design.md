# Scalar List Canonical Marshal Design

## Scope

This change promotes the synchronous, value-only canonical marshal route from
the existing `list<u8>` and `list<u32>` shapes to scalar lists whose elements
are `bool`, `u8`, `u16`, `u32`, `u64`, `i32`, `i64`, `f32`, or `f64`.

The route remains bounded and measured. It does not admit text elements,
records, resources, nested lists, async values, or borrowed/owned payloads.

## Representation

The canonical list value is always a `(ptr, len)` pair. The list payload is a
contiguous linear-memory span. Its element size, alignment, stride, and core
word come from the scalar element kind:

| element | byte size | alignment | stride | core word | linear load/store |
| --- | ---: | ---: | ---: | --- | --- |
| `bool` | 1 | 1 | 1 | `i32` | `i32.load8_u` / `i32.store8` |
| `u8` | 1 | 1 | 1 | `i32` | `i32.load8_u` / `i32.store8` |
| `u16` | 2 | 2 | 2 | `i32` | `i32.load16_u` / `i32.store16` |
| `u32`, `i32` | 4 | 4 | 4 | `i32` | `i32.load` / `i32.store` |
| `u64`, `i64` | 8 | 8 | 8 | `i64` | `i64.load` / `i64.store` |
| `f32` | 4 | 4 | 4 | `f32` | `f32.load` / `f32.store` |
| `f64` | 8 | 8 | 8 | `f64` | `f64.load` / `f64.store` |

The measured child facts and list facts must agree with this table. A shape
with a mismatched size, alignment, stride, or core word is rejected before WAT
emission.

## GC boundary

The GC side uses the existing typed scalar arrays. The canonical ABI never
receives a GC reference:

```text
GC array<T> -> allocate ptr/len span -> copy typed elements -> canonical call
canonical result ptr/len -> typed array<T> -> free result span
```

Zero length is valid. The allocation path still uses `cabi_realloc`; a zero
byte payload is represented by a zero copy count and follows the existing
span guard and cleanup order.

## Non-goals

- General `list<T>` lowering for text, records, resources, or nested lists.
- Tuple or map generalization.
- Async or stream payloads.
- Changes to the Do source collection semantics.
