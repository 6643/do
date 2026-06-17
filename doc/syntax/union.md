# 联合类型

规则: 顶层 type alias / union alias 已取消; 不写 `ReadResult = [u8] | FileError` 或 `MaybeUser = User | nil`。需要 union 时, 直接在返回位、字段、局部绑定、storage 元素或 type args 中写平铺 union。

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

## 分支提取

```do
if @is(user, User) {
    value User = @as(user, User)
    return value
}

if @is(result, FileError) {
    err FileError = @as(result, FileError)
    return err
}
```

规则: `@as(value, Type)` 只做 union payload 提取, 不做类型转换。`Type` 必须是 `value` 静态 union 中唯一的非 `nil` 类型分支; `nil` 分支继续用 `@eq(value, nil)` 判断, 不能提取 payload。提取前推荐使用 `@is(value, Type)` guard, 否则读取到的 payload 是否对应当前 tag 不由 `@as` 自动证明。
