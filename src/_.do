// builtin/core declaration table.
// Loaded implicitly by the compiler; not a normal import target.

// Special forms
// is(value, TypeExpr) -> bool
// and(a bool, b bool, rest ...bool) -> bool
// or(a bool, b bool, rest ...bool) -> bool
// not(value bool) -> bool

// Core predicates
// eq(a T, b T) -> bool
// ne(a T, b T) -> bool
// lt(a T, b T) -> bool
// le(a T, b T) -> bool
// gt(a T, b T) -> bool
// ge(a T, b T) -> bool

// Core numeric operators
// add(a T, b T, rest ...T) -> T
// sub(a T, b T, rest ...T) -> T
// mul(a T, b T, rest ...T) -> T
// div(a T, b T, rest ...T) -> T
// rem(a T, b T, rest ...T) -> T

// Core storage primitives
// len(xs [T]) -> usize
// at(xs [T], i usize) -> T
// get(xs [T], i usize) -> T
// set(xs [T], i usize, value T) -> [T]

// Structure field primitives
// get(value T, .name) -> U
// set(value T, .name, value U) -> T

// Core conversions
// to_u8(x T) -> u8
// to_u16(x T) -> u16
// to_u32(x T) -> u32
// to_u64(x T) -> u64
// to_usize(x T) -> usize
// to_i8(x T) -> i8
// to_i16(x T) -> i16
// to_i32(x T) -> i32
// to_i64(x T) -> i64
// to_f32(x T) -> f32
// to_f64(x T) -> f64

// Notes:
// - `to_*` names are ordinary API surface, not reserved builtin names.
// - `to_text` and `Text` live in std and are intentionally not listed here.
// - Library types like `List` and `HashMap` stay in `src/*.do`.
