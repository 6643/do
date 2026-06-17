// builtin/core declaration table.
// Loaded implicitly by the compiler; not a normal import target.
//
// Core intrinsic overloads below are closed compiler signatures, not source
// generics. Users and std cannot add signatures.

// Special forms
// @is(value, TypeExpr) -> bool
// @and(a bool, b bool, ...bool) -> bool
//   source args: 2+, no spread
// @or(a bool, b bool, ...bool) -> bool
//   source args: 2+, no spread
// @not(value bool) -> bool

// Core predicates
// @eq(a, b) -> bool
// @ne(a, b) -> bool
//   a and b must be the same concrete comparable type.
// @lt/@le/@gt/@ge(i8, i8) -> bool
// @lt/@le/@gt/@ge(i16, i16) -> bool
// @lt/@le/@gt/@ge(i32, i32) -> bool
// @lt/@le/@gt/@ge(i64, i64) -> bool
// @lt/@le/@gt/@ge(isize, isize) -> bool
// @lt/@le/@gt/@ge(u8, u8) -> bool
// @lt/@le/@gt/@ge(u16, u16) -> bool
// @lt/@le/@gt/@ge(u32, u32) -> bool
// @lt/@le/@gt/@ge(u64, u64) -> bool
// @lt/@le/@gt/@ge(usize, usize) -> bool
// @lt/@le/@gt/@ge(f32, f32) -> bool
// @lt/@le/@gt/@ge(f64, f64) -> bool

// Core numeric operators
// @add/@sub/@mul/@div(i8, i8, ...i8) -> i8
// @add/@sub/@mul/@div(i16, i16, ...i16) -> i16
// @add/@sub/@mul/@div(i32, i32, ...i32) -> i32
// @add/@sub/@mul/@div(i64, i64, ...i64) -> i64
// @add/@sub/@mul/@div(isize, isize, ...isize) -> isize
// @add/@sub/@mul/@div(u8, u8, ...u8) -> u8
// @add/@sub/@mul/@div(u16, u16, ...u16) -> u16
// @add/@sub/@mul/@div(u32, u32, ...u32) -> u32
// @add/@sub/@mul/@div(u64, u64, ...u64) -> u64
// @add/@sub/@mul/@div(usize, usize, ...usize) -> usize
// @add/@sub/@mul/@div(f32, f32, ...f32) -> f32
// @add/@sub/@mul/@div(f64, f64, ...f64) -> f64
// @rem(i8, i8, ...i8) -> i8
// @rem(i16, i16, ...i16) -> i16
// @rem(i32, i32, ...i32) -> i32
// @rem(i64, i64, ...i64) -> i64
// @rem(isize, isize, ...isize) -> isize
// @rem(u8, u8, ...u8) -> u8
// @rem(u16, u16, ...u16) -> u16
// @rem(u32, u32, ...u32) -> u32
// @rem(u64, u64, ...u64) -> u64
// @rem(usize, usize, ...usize) -> usize
//   @add/@sub/@mul/@div/@rem source calls with 3+ args lower left-associatively
//   spread requires at least two fixed source args before ...rest
// @abs(i8) -> u8
// @abs(i16) -> u16
// @abs(i32) -> u32
// @abs(i64) -> u64
// @abs(isize) -> usize
// @abs(f32) -> f32
// @abs(f64) -> f64
// @min(i8, i8, ...i8) -> i8
// @min(i16, i16, ...i16) -> i16
// @min(i32, i32, ...i32) -> i32
// @min(i64, i64, ...i64) -> i64
// @min(isize, isize, ...isize) -> isize
// @min(u8, u8, ...u8) -> u8
// @min(u16, u16, ...u16) -> u16
// @min(u32, u32, ...u32) -> u32
// @min(u64, u64, ...u64) -> u64
// @min(usize, usize, ...usize) -> usize
// @min(f32, f32, ...f32) -> f32
// @min(f64, f64, ...f64) -> f64
// @max(i8, i8, ...i8) -> i8
// @max(i16, i16, ...i16) -> i16
// @max(i32, i32, ...i32) -> i32
// @max(i64, i64, ...i64) -> i64
// @max(isize, isize, ...isize) -> isize
// @max(u8, u8, ...u8) -> u8
// @max(u16, u16, ...u16) -> u16
// @max(u32, u32, ...u32) -> u32
// @max(u64, u64, ...u64) -> u64
// @max(usize, usize, ...usize) -> usize
// @max(f32, f32, ...f32) -> f32
// @max(f64, f64, ...f64) -> f64
//   @min/@max source calls with 3+ args lower left-associatively
//   spread requires at least two fixed source args before ...rest

// Core bitwise operators
// @and/@or/@xor(i8, i8) -> i8
// @and/@or/@xor(i16, i16) -> i16
// @and/@or/@xor(i32, i32) -> i32
// @and/@or/@xor(i64, i64) -> i64
// @and/@or/@xor(isize, isize) -> isize
// @and/@or/@xor(u8, u8) -> u8
// @and/@or/@xor(u16, u16) -> u16
// @and/@or/@xor(u32, u32) -> u32
// @and/@or/@xor(u64, u64) -> u64
// @and/@or/@xor(usize, usize) -> usize
// @shl/@shr/@rotl/@rotr(i8, usize) -> i8
// @shl/@shr/@rotl/@rotr(i16, usize) -> i16
// @shl/@shr/@rotl/@rotr(i32, usize) -> i32
// @shl/@shr/@rotl/@rotr(i64, usize) -> i64
// @shl/@shr/@rotl/@rotr(isize, usize) -> isize
// @shl/@shr/@rotl/@rotr(u8, usize) -> u8
// @shl/@shr/@rotl/@rotr(u16, usize) -> u16
// @shl/@shr/@rotl/@rotr(u32, usize) -> u32
// @shl/@shr/@rotl/@rotr(u64, usize) -> u64
// @shl/@shr/@rotl/@rotr(usize, usize) -> usize
// @clz/@ctz/@popcnt(i8) -> i8
// @clz/@ctz/@popcnt(i16) -> i16
// @clz/@ctz/@popcnt(i32) -> i32
// @clz/@ctz/@popcnt(i64) -> i64
// @clz/@ctz/@popcnt(isize) -> isize
// @clz/@ctz/@popcnt(u8) -> u8
// @clz/@ctz/@popcnt(u16) -> u16
// @clz/@ctz/@popcnt(u32) -> u32
// @clz/@ctz/@popcnt(u64) -> u64
// @clz/@ctz/@popcnt(usize) -> usize

// Core float operators
// @neg(f32) -> f32
// @neg(f64) -> f64
// @sqrt(f32) -> f32
// @sqrt(f64) -> f64
// @ceil(f32) -> f32
// @ceil(f64) -> f64
// @floor(f32) -> f32
// @floor(f64) -> f64
// @trunc(f32) -> f32
// @trunc(f64) -> f64
// @nearest(f32) -> f32
// @nearest(f64) -> f64
// @copysign(f32, f32) -> f32
// @copysign(f64, f64) -> f64

// Core storage primitives
// @len(xs [T]) -> usize
// @get(xs [T], i usize) -> T
// @set(xs [T], i usize, value T) -> [T]
// @put(xs [T], value T, rest ...T) -> [T]

// Structure field primitives
// @get(value T, .name) -> U
// @set(value T, .name, value U) -> T

// Core conversions
// @as(u8, u8) -> u8
// @as(u8, u16) -> u8
// @as(u8, u32) -> u8
// @as(u8, u64) -> u8
// @as(u8, usize) -> u8
// @as(u8, i8) -> u8
// @as(u8, i16) -> u8
// @as(u8, i32) -> u8
// @as(u8, i64) -> u8
// @as(u8, isize) -> u8
// @as(u8, f32) -> u8
// @as(u8, f64) -> u8
// @as(u16, u8) -> u16
// @as(u16, u16) -> u16
// @as(u16, u32) -> u16
// @as(u16, u64) -> u16
// @as(u16, usize) -> u16
// @as(u16, i8) -> u16
// @as(u16, i16) -> u16
// @as(u16, i32) -> u16
// @as(u16, i64) -> u16
// @as(u16, isize) -> u16
// @as(u16, f32) -> u16
// @as(u16, f64) -> u16
// @as(u32, u8) -> u32
// @as(u32, u16) -> u32
// @as(u32, u32) -> u32
// @as(u32, u64) -> u32
// @as(u32, usize) -> u32
// @as(u32, i8) -> u32
// @as(u32, i16) -> u32
// @as(u32, i32) -> u32
// @as(u32, i64) -> u32
// @as(u32, isize) -> u32
// @as(u32, f32) -> u32
// @as(u32, f64) -> u32
// @as(u64, u8) -> u64
// @as(u64, u16) -> u64
// @as(u64, u32) -> u64
// @as(u64, u64) -> u64
// @as(u64, usize) -> u64
// @as(u64, i8) -> u64
// @as(u64, i16) -> u64
// @as(u64, i32) -> u64
// @as(u64, i64) -> u64
// @as(u64, isize) -> u64
// @as(u64, f32) -> u64
// @as(u64, f64) -> u64
// @as(usize, u8) -> usize
// @as(usize, u16) -> usize
// @as(usize, u32) -> usize
// @as(usize, u64) -> usize
// @as(usize, usize) -> usize
// @as(usize, i8) -> usize
// @as(usize, i16) -> usize
// @as(usize, i32) -> usize
// @as(usize, i64) -> usize
// @as(usize, isize) -> usize
// @as(usize, f32) -> usize
// @as(usize, f64) -> usize
// @as(i8, u8) -> i8
// @as(i8, u16) -> i8
// @as(i8, u32) -> i8
// @as(i8, u64) -> i8
// @as(i8, usize) -> i8
// @as(i8, i8) -> i8
// @as(i8, i16) -> i8
// @as(i8, i32) -> i8
// @as(i8, i64) -> i8
// @as(i8, isize) -> i8
// @as(i8, f32) -> i8
// @as(i8, f64) -> i8
// @as(i16, u8) -> i16
// @as(i16, u16) -> i16
// @as(i16, u32) -> i16
// @as(i16, u64) -> i16
// @as(i16, usize) -> i16
// @as(i16, i8) -> i16
// @as(i16, i16) -> i16
// @as(i16, i32) -> i16
// @as(i16, i64) -> i16
// @as(i16, isize) -> i16
// @as(i16, f32) -> i16
// @as(i16, f64) -> i16
// @as(i32, u8) -> i32
// @as(i32, u16) -> i32
// @as(i32, u32) -> i32
// @as(i32, u64) -> i32
// @as(i32, usize) -> i32
// @as(i32, i8) -> i32
// @as(i32, i16) -> i32
// @as(i32, i32) -> i32
// @as(i32, i64) -> i32
// @as(i32, isize) -> i32
// @as(i32, f32) -> i32
// @as(i32, f64) -> i32
// @as(i64, u8) -> i64
// @as(i64, u16) -> i64
// @as(i64, u32) -> i64
// @as(i64, u64) -> i64
// @as(i64, usize) -> i64
// @as(i64, i8) -> i64
// @as(i64, i16) -> i64
// @as(i64, i32) -> i64
// @as(i64, i64) -> i64
// @as(i64, isize) -> i64
// @as(i64, f32) -> i64
// @as(i64, f64) -> i64
// @as(isize, u8) -> isize
// @as(isize, u16) -> isize
// @as(isize, u32) -> isize
// @as(isize, u64) -> isize
// @as(isize, usize) -> isize
// @as(isize, i8) -> isize
// @as(isize, i16) -> isize
// @as(isize, i32) -> isize
// @as(isize, i64) -> isize
// @as(isize, isize) -> isize
// @as(isize, f32) -> isize
// @as(isize, f64) -> isize
// @as(f32, u8) -> f32
// @as(f32, u16) -> f32
// @as(f32, u32) -> f32
// @as(f32, u64) -> f32
// @as(f32, usize) -> f32
// @as(f32, i8) -> f32
// @as(f32, i16) -> f32
// @as(f32, i32) -> f32
// @as(f32, i64) -> f32
// @as(f32, isize) -> f32
// @as(f32, f32) -> f32
// @as(f32, f64) -> f32
// @as(f64, u8) -> f64
// @as(f64, u16) -> f64
// @as(f64, u32) -> f64
// @as(f64, u64) -> f64
// @as(f64, usize) -> f64
// @as(f64, i8) -> f64
// @as(f64, i16) -> f64
// @as(f64, i32) -> f64
// @as(f64, i64) -> f64
// @as(f64, isize) -> f64
// @as(f64, f32) -> f64
// @as(f64, f64) -> f64

// Notes:
// - builtin/core names are fixed and cannot be user-declared, imported as aliases,
//   shadowed, or used as interface constraint names.
// - `to_text` lives in std and is intentionally not listed here.
// - Library types like `List` and `HashMap` stay in `src/*.do`.
