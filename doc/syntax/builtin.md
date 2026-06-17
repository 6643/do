# 内建调用

## 分支判断

```do
// 判断命名类型分支
@is(value, User)

// 判断多个类型分支
@is(value, User | Admin)

// 判断连续存储分支
@is(value, [User])

// 判断泛型类型分支
@is(value, Box<User | nil>)

// 判断错误枚举分支
@is(value, FileError)
```

规则: `@is(value, TypeExpr)` 只做类型分支判断, 第二个实参必须是类型表达式。`value enum` 的分支值和 `nil` 都是值, 统一使用 `@eq/@ne` 判断, 不写成 `@is(value, ByteDigit)` 或 `@is(value, nil)`。

## 逻辑

```do
// 两项 and
@and(a, b)

// 多项 and
@and(a, b, c)

// 两项 or
@or(a, b)

// 多项 or
@or(a, b, c)

// not
@not(a)
```

规则: `@and/@or/@not` 在 bool 条件和 bool 表达式上按逻辑 special form 处理, `@and/@or` 可短路。整数参数上的 `@and/@or` 是位运算 core 固定调用名, 不按 bool 短路语义执行。

## 比较

```do
// 等于
@eq(a, b)

// 不等于
@ne(a, b)

// 小于
@lt(a, b)

// 小于等于
@le(a, b)

// 大于
@gt(a, b)

// 大于等于
@ge(a, b)
```

## 算术

```do
// 两项加法
@add(a, b)

// 多项加法
@add(a, b, c)

// spread 加法
@add(a, ...rest)

// 减法
@sub(a, b)

// 乘法
@mul(a, b)

// 除法
@div(a, b)

// 取余
@rem(a, b)

// 绝对值
@abs(a)

// 两项最小值
@min(a, b)

// 多项最小值
@min(a, b, c)

// 两项最大值
@max(a, b)

// 多项最大值
@max(a, b, c)
```

## 位运算

```do
// 按位 and
@and(a, b)

// 按位 or
@or(a, b)

// 按位 xor
@xor(a, b)

// 左移
@shl(a, bits)

// 右移
@shr(a, bits)

// 循环左移
@rotl(a, bits)

// 循环右移
@rotr(a, bits)

// 前导零计数
@clz(a)

// 尾随零计数
@ctz(a)

// 置位计数
@popcnt(a)
```

规则: 位运算只接受整数标量。`@and/@or` 与逻辑调用共用表面名字, 由静态类型区分; bool 参数走逻辑语义, integer 参数走位运算语义。

## 浮点

```do
// 取负
@neg(a)

// 平方根
@sqrt(a)

// 向上取整
@ceil(a)

// 向下取整
@floor(a)

// 截断
@trunc(a)

// 最近整数
@nearest(a)

// 复制符号
@copysign(a, sign)
```

## 连续存储

```do
// 读取长度
@len(items)

// 追加单值
@put(items, value)

// 追加多值
@put(items, first, second)

// spread 追加
@put(items, ...rest)
```

规则: 连续存储内建只接受 `[T]`。`text` 不是 `[u8]` alias, 不能直接传给 `@len/@get/@set/@put/@load_*`; 需要字节视图时通过文本库显式转换。`@put(items, value...)` 可追加一个或多个显式值; `@put(items, ...rest)` 是 spread 追加语法, build lowering 必须按该形态单独落地。

## 路径读取和更新

```do
// 字段读取
@get(user, .name)

// 索引读取
@get(items, index)

// 多段路径读取
@get(state, .users, index, .name)

// 字段更新
@set(user, .name, "amy")

// 索引更新
@set(items, index, value)

// 多段路径更新
@set(state, .users, index, .name, "amy")

// lambda 更新
@set(counter, .count, (value i32) => @add(value, 1))
```

## 字段反射

```do
// 字段名
@field_name(field)

// 可见字段顺序 index
@field_index(field)

// 字段是否声明默认值
@field_has_default(field)

// 读取字段值
@field_get(user, field)

// 更新字段值
user = @field_set(user, field, value)
```

规则: 字段反射内建只能使用 `fields(TypeOrTypeParam)` 循环绑定产生的字段元数据。`TypeOrTypeParam` 是具体结构体名, 或泛型函数实例中已绑定为具体结构体的单个类型参数名。`@field_get/@field_set` 在每个字段展开点使用该字段的静态类型; `@field_get(value, field)` 作为普通调用实参时按字段类型参与重载分派。当前 build lowering 只支持 `target = @field_set(target, field, value)` 这种同名自赋值形态。不提供 `@field_type`、`@field_default_value` 或 `@field_default_type`。

## 定宽读取

```do
// u8 读取
@load_u8(bytes, index)

// i8 读取
@load_i8(bytes, index)

// little-endian u16 读取
@load_u16_le(bytes, index)

// little-endian i16 读取
@load_i16_le(bytes, index)

// little-endian u32 读取
@load_u32_le(bytes, index)

// little-endian i32 读取
@load_i32_le(bytes, index)

// little-endian u64 读取
@load_u64_le(bytes, index)

// little-endian i64 读取
@load_i64_le(bytes, index)
```

## 数值转换

```do
// 转 u8
@to_u8(value)

// 转 u16
@to_u16(value)

// 转 u32
@to_u32(value)

// 转 u64
@to_u64(value)

// 转 usize
@to_usize(value)

// 转 isize
@to_isize(value)

// 转 i8
@to_i8(value)

// 转 i16
@to_i16(value)

// 转 i32
@to_i32(value)

// 转 i64
@to_i64(value)

// 转 f32
@to_f32(value)

// 转 f64
@to_f64(value)
```
