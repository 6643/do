# 泛型

## 结构体类型参数

```do
// 单类型参数结构体
#T
Box {
    value T
}

// 多类型参数结构体
#K
#V
Entry {
    key K
    value V
}
```

## 泛型类型使用

```do
// 单类型实参
Box<i32>

// 联合类型实参
Box<User | nil>

// 多类型实参
Entry<text, User>
```

## 泛型函数

```do
// 单类型参数函数
#T
id(value T) -> T {
    return value
}

// 类型参数加同类型变参
#T
first(value T, rest ...T) -> T {
    return value
}
```

## 显式泛型调用

```do
// 调用点显式绑定函数类型参数
x = id<i32>(1)

// `from_json` 不使用返回上下文反推目标类型, 调用点显式写类型实参
user = from_json<User>(bytes)
```

## 函数类型参数

```do
// 单返回函数类型参数
#F = (i32) -> text
render(f F, value i32) -> text {
    return f(value)
}

// 多返回函数类型参数
#F = (i32) -> i32, bool
compute(f F, value i32) -> i32, bool {
    return f(value)
}
```

## 接口函数约束

```do
// 普通接口函数约束
#T
#same(T, T) -> bool
same_pair(a T, b T) -> bool {
    return same(a, b)
}

// 带变参的接口函数约束
#T
#combine(T, T, ...T) -> T
combine_all(first T, second T, rest ...T) -> T {
    return combine(first, second, ...rest)
}
```

## 组合约束

```do
// 数据类型参数 + 函数类型参数 + 接口函数约束
#T
#F = (T) -> text
#same(T, T) -> bool
format_if_same(a T, b T, f F) -> text | nil {
    if same(a, b) return f(a)
    return nil
}
```
