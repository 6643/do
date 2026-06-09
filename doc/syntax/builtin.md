# 内建调用

## 分支判断

```do
@is(value, User)            // 判断命名类型分支
@is(value, User | Admin)    // 判断多个类型分支
@is(value, [User])          // 判断连续存储分支
@is(value, Box<User | nil>) // 判断泛型类型分支
@is(value, FileError)       // 判断错误枚举分支
```

规则: `@is(value, TypeExpr)` 只做类型分支判断, 第二个实参必须是类型表达式。值比较使用 `@eq/@ne`; `nil` 判断使用值比较或 nullable helper, 不写成 `@is(value, nil)`。

## 逻辑

```do
@and(a, b)    // 两项 and
@and(a, b, c) // 多项 and
@or(a, b)     // 两项 or
@or(a, b, c)  // 多项 or
@not(a)       // not
```

## 比较

```do
@eq(a, b) // 等于
@ne(a, b) // 不等于
@lt(a, b) // 小于
@le(a, b) // 小于等于
@gt(a, b) // 大于
@ge(a, b) // 大于等于
```

## 算术

```do
@add(a, b)       // 两项加法
@add(a, b, c)    // 多项加法
@add(a, ...rest) // spread 加法
@sub(a, b)       // 减法
@mul(a, b)       // 乘法
@div(a, b)       // 除法
@rem(a, b)       // 取余
@abs(a)          // 绝对值
@min(a, b)       // 两项最小值
@min(a, b, c)    // 多项最小值
@max(a, b)       // 两项最大值
@max(a, b, c)    // 多项最大值
```

## 位运算

```do
@and(a, b)       // 按位 and
@or(a, b)        // 按位 or
@xor(a, b)       // 按位 xor
@shl(a, bits)    // 左移
@shr(a, bits)    // 右移
@rotl(a, bits)   // 循环左移
@rotr(a, bits)   // 循环右移
@clz(a)          // 前导零计数
@ctz(a)          // 尾随零计数
@popcnt(a)       // 置位计数
```

## 浮点

```do
@neg(a)             // 取负
@sqrt(a)            // 平方根
@ceil(a)            // 向上取整
@floor(a)           // 向下取整
@trunc(a)           // 截断
@nearest(a)         // 最近整数
@copysign(a, sign)  // 复制符号
```

## 连续存储

```do
@len(items)                // 读取长度
@put(items, value)         // 追加单值
@put(items, first, second) // 追加多值
@put(items, ...rest)       // spread 追加
```

规则: 连续存储内建只接受 `[T]`。`text` 不是 `[u8]` alias, 不能直接传给 `@len/@get/@set/@put/@load_*`; 需要字节视图时通过文本库显式转换。`@put(items, value...)` 可追加一个或多个显式值; `@put(items, ...rest)` 是 spread 追加语法, build lowering 必须按该形态单独落地。

## 路径读取和更新

```do
@get(user, .name)                // 字段读取
@get(items, index)               // 索引读取
@get(state, .users, index, .name) // 多段路径读取

@set(user, .name, "amy")                         // 字段更新
@set(items, index, value)                        // 索引更新
@set(state, .users, index, .name, "amy")          // 多段路径更新
@set(counter, .count, (value i32) => @add(value, 1)) // lambda 更新
```

## 定宽读取

```do
@load_u8(bytes, index)      // u8 读取
@load_i8(bytes, index)      // i8 读取
@load_u16_le(bytes, index)  // little-endian u16 读取
@load_i16_le(bytes, index)  // little-endian i16 读取
@load_u32_le(bytes, index)  // little-endian u32 读取
@load_i32_le(bytes, index)  // little-endian i32 读取
@load_u64_le(bytes, index)  // little-endian u64 读取
@load_i64_le(bytes, index)  // little-endian i64 读取
```

## 数值转换

```do
@to_u8(value)    // 转 u8
@to_u16(value)   // 转 u16
@to_u32(value)   // 转 u32
@to_u64(value)   // 转 u64
@to_usize(value) // 转 usize
@to_isize(value) // 转 isize
@to_i8(value)    // 转 i8
@to_i16(value)   // 转 i16
@to_i32(value)   // 转 i32
@to_i64(value)   // 转 i64
@to_f32(value)   // 转 f32
@to_f64(value)   // 转 f64
```
