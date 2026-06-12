# 函数

## 函数声明

```do
// 无显式返回类型的 nil 函数
ready() {
    return
}

// 显式 nil 返回函数
log(message text) -> nil {
    return
}

// 单返回函数
add(a i32, b i32) -> i32 {
    return @add(a, b)
}

// 多返回函数
pair() -> i32, bool {
    return 1, true
}

// 私有函数声明
.internal(value i32) -> i32 {
    return value
}
```

## 表达式体

```do
// 单返回表达式体
add(a i32, b i32) -> i32 => @add(a, b)

// 多返回表达式体
pair() -> i32, bool => 1, true
```

## 参数

```do
// 无参数
empty() -> nil {
    return
}

// 单参数
one(value i32) -> i32 {
    return value
}

// 参数可重新赋值
inc(value i32) -> i32 {
    value = @add(value, 1)
    return value
}

// 多参数
many(id i64, name text, active bool) -> User {
    return User{id = id, name = name, active = active}
}
```

规则: 函数参数必须显式写类型, 不支持 `value` 这种只写参数名的省略形式。参数名使用 `snake_case`, 不使用 `_name` 只读名, 也不能和当前可见普通函数名、函数 import alias 或 host import alias 同名。参数绑定是可写局部绑定, 命中后赋值会更新当前参数值, 不会创建新的同名局部声明。

## 同类型变参

```do
// 固定参数加尾部变参
sum(first i32, rest ...i32) -> i32 {
    total i32 = first
    loop value, _ = rest {
        total = @add(total, value)
    }
    return total
}

// 纯尾部变参
collect(rest ...i32) -> [i32] {
    return @put(.{}, ...rest)
}
```

规则: 函数 ABI symbol 按模块、参数签名和泛型实例 mangle。overload resolution 按实参形状筛唯一候选, 不能只靠返回类型区分 overload。同名同 arity 的具体 overload 可以和泛型 fallback 共存; 调用先选精确具体签名, 无具体匹配时才实例化泛型 fallback。两个泛型同名同 arity 直接视为重复或歧义。`...T` 只表达同类型尾参, 不表达异构参数链; variadic 和 generic instance 参与同一套 mangle 与候选筛选规则。

## 返回

```do
// nil 返回
done() -> nil {
    return
}

// 单值返回
one() -> i32 {
    return 1
}

// 多值返回
two() -> i32, bool {
    return 1, true
}
```
