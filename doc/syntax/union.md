# 联合类型

规则: 源码没有顶层类型别名声明。需要 union 时, 直接在返回位、字段、局部绑定、普通固定数据参数、storage 元素或 type args 中写平铺 union。

## 可空类型

```do
// 结构体可空类型
user User | nil = nil

// 文本可空类型
name text | nil = nil
```

## 联合返回

```do
// 可空返回
find_user(id i64) -> User | nil {
    return nil
}

// 值或错误返回
read_file(path text) -> [u8] | FileError {
    return FileNotFound
}

// 值、错误或 nil 返回
read_optional(path text) -> [u8] | FileError | nil {
    return nil
}
```

## 联合绑定

```do
// 可空联合绑定
user User | nil = find_user(1)

// 值或错误联合绑定
result [u8] | FileError = read_file("a.txt")
```

## 联合参数

```do
emit(value text | nil) -> [u8] {
    if @eq(value, nil) return "null"
    return value
}
```

规则: 普通固定数据参数可写平铺 union/nullable。变参元素、函数类型约束参数、lambda 参数和接口约束参数不接收 union/nullable; `F | nil` 不能表达可选回调。

## 分支判断

```do
// 判断结构分支
if @is(user, User) {
    return user
}

// 判断错误枚举分支
if @is(result, FileError) {
    return result
}

// 判断多个非 nil 分支
if @is(value, User | Admin) {
    return value
}

// 判断泛型类型分支
if @is(box, Box<User | nil>) {
    return box
}
```

规则: union lowering 使用统一 runtime tag representation。`@is(value, TypeExpr)` 的第二个实参只能是类型表达式; `nil` 是值分支, 判断 nil 使用 `@eq(value, nil)` 或 nullable helper, 不写成 `@is(value, nil)`。

`@eq(value, nil)` / `@ne(value, nil)` 在条件位对 nullable union 做路径收紧。若 `value` 只有一个非 `nil` 分支, `@ne(value, nil)` 的 true 分支可把 `value` 当作该分支类型使用; `@eq(value, nil)` 的 false 分支和 guard-return 后续路径也同理。复杂 union 使用 `@is(value, Type)` 明确分支。

## 分支收紧

```do
if @is(user, User) {
    value User = user
    return value
}

if @is(result, FileError) {
    err FileError = result
    return err
}
```

规则: `@is(value, Type)` 的 true 分支会把 `value` 收紧为 `Type`, 分支内直接使用原变量。标量数值转换继续使用 `@as(Type, value)`。
