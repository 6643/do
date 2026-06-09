# 联合类型

## 联合别名

```do
// 值或错误联合别名
ReadResult = [u8] | FileError

// 多结构分支联合别名
Value = User | Admin
```

## 可空类型

```do
// 结构体可空类型
MaybeUser = User | nil

// 文本可空类型
MaybeText = text | nil
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
