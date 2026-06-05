// builtin/core declaration table.
// Loaded implicitly by the compiler; not a normal import target.

// Special forms
// is(value, TypeExpr) -> bool
// and(a bool, b bool, ...) -> bool
//   source args: 2+, no spread
// or(a bool, b bool, ...) -> bool
//   source args: 2+, no spread
// not(value bool) -> bool

// Core predicates
// eq(a T, b T) -> bool
// ne(a T, b T) -> bool
// lt(a T, b T) -> bool
// le(a T, b T) -> bool
// gt(a T, b T) -> bool
// ge(a T, b T) -> bool

// Core numeric operators
// add(a T, b T) -> T
// sub(a T, b T) -> T
// mul(a T, b T) -> T
// div(a T, b T) -> T
// rem(a T, b T) -> T
//   source calls with 3+ args lower left-associatively
//   spread requires at least two fixed source args before ...rest

// Core storage primitives
// len(xs [T]) -> usize
// get(xs [T], i usize) -> T
// set(xs [T], i usize, value T) -> [T]
// put(xs [T], value T, rest ...T) -> [T]

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
// - builtin/core names are fixed and cannot be user-declared, imported as aliases,
//   shadowed, or used as interface constraint names.
// - `to_text` lives in std and is intentionally not listed here.
// - Library types like `List` and `HashMap` stay in `src/*.do`.
