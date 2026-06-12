# 表达式

## 字面量

```do
// 整数字面量
1

// 浮点字面量
3.14

// 字符串字面量
"hello"

// bool true
true

// bool false
false

// nil 字面量
nil
```

## 行字符串

```do
// 行字符串绑定
message text =
    \\hello
    \\world
```

规则: 行字符串只在 `=` 右侧的表达式根位直接出现。`return`、调用实参、结构字段初始化和聚合元素不能直接写行字符串; 需要先绑定到局部值再引用。

```do
make_text() -> text {
    text_value text =
        \\hello

    return text_value
}
```

## 名字

```do
// 普通值名
value

// 只读值名
_limit

// 枚举分支值名
OrderCreated
```

## 括号

```do
// 普通括号表达式
(value)

// 内建调用括号表达式
(@add(a, b))
```

## 调用

```do
// 无参数调用
ready()

// 固定参数调用
add(1, 2)

// 多实参调用
sum(1, 2, 3)

// 固定实参加 spread 实参
sum(1, ...items)

// 纯 spread 实参调用
collect(...items)
```

## lambda

```do
// 无参数 block lambda 实参
run(() -> nil {
    return
})

// 带类型参数的 block lambda 实参
map(items, (value i32) -> i32 {
    return @add(value, 1)
})

// 目标返回类型是 nil 时, block lambda 可省略 `-> nil`
tap(value, (item i32) {
    _ = @add(item, 1)
    return
})

// 带类型参数的表达式体 lambda 实参
map(items, (value i32) -> i32 => @add(value, 1))

// 推导参数类型的 lambda 更新值
state = @set(state, .count, (value) => @add(value, 1))
```

规则: lambda 不是闭包, 不能捕获外层局部绑定, 不能绑定到变量或作为值返回。lambda 只出现在普通调用实参位, 或 `@set(..., lambda)` 这类 primitive 明确接收 value 的位置。参数类型省略时, 必须由已选中的目标 `FuncType` 提供参数类型; block lambda 省略返回类型时, 只允许目标返回类型已经确定, 且为 `nil` 时可进一步省略 `-> nil` 写成 `(x T) { ... }`。

## 聚合

```do
// 空 typed 聚合
User{}

// typed 字段聚合
User{id = 1, name = "tom"}

// typed 字段聚合带尾逗号
User{id = 1, name = "tom",}

// 空推导聚合
.{}

// 推导元素聚合
.{1, 2, 3}

// 推导字段聚合
.{id = 1, name = "tom"}
```

## 表达式语句

```do
// 无参数调用语句
ready()

// 带参数调用语句
log("done")
```
