# 控制

## 块

```do
// 普通块
{
    value i32 = 1
    return
}
```

## if 块

```do
// 单分支 if
if ready {
    return
}

// if / else
if ready {
    return
} else {
    return
}

// if / else if / else
if ready {
    return
} else if fallback {
    return
} else {
    return
}
```

## if 值表达式

值 `if` 用于在表达式位置按条件选择一个值. 两个分支都必须存在, 并产生兼容的值. 分支可以是普通表达式或带尾值的代码块, 代码块最后一个表达式作为块值.

```do
count i32 = if b {1} else {2}
count i32 = if b 1 else 2

count i32 = if b {
    print("b == 1")
    1
} else 2

// Tuple 在这里作为一个值, 两边类型和 arity 必须一致.
pair Tuple<i32, bool> = if b .{1, true} else .{2, false}

// 嵌套 if 的 else 绑定到最近尚未匹配的 if.
value i32 = if a if b 1 else 2 else 3
```

值块遵守词法作用域, 块内绑定不能在块外或另一个分支中使用. 块内的 `defer` 在离开值块时执行; 尾值先保存, cleanup 按 LIFO 顺序执行, 然后产生尾值.

Tuple 值分支当前只支持 scalar slot 元素; managed 或嵌套聚合 Tuple 分支暂未支持.

## guard if

```do
// guard return
if ready return

// guard 单值 return
if ready return value

// guard 多值 return
if ready return a, b

// guard break
if done break

// guard continue
if skip continue

// guard 带标签 break
if done break #outer

// guard 带标签 continue
if skip continue #outer
```

## return

```do
// nil return
return

// 单值 return
return value

// 多值 return
return a, b
```

## defer

```do
// defer 调用目标函数
abc() -> nil {
    return
}

work() -> nil {
    should_close bool = true
    should_log bool = false

    // defer 调用
    defer abc()

    // 仅在注册时条件为 true 时执行 cleanup.
    defer(should_close) abc()

    // defer 块
    defer {
        print("defer")
    }

    // 带条件的 defer 块.
    defer(should_log) {
        print("cleanup")
    }

    return
}
```

`defer` 离开当前词法区域时执行。条件 defer 在注册时保存条件值, 后续修改条件不会改变 cleanup 是否运行。cleanup 调用及参数在区域退出时求值, 与普通 `defer` 一致。循环体每轮是独立的区域执行; `continue`、`break` 和 `return` 离开区域时按 LIFO 顺序执行 cleanup。

```do
cleanup() -> nil {
    return
}

use() {
    loop {
        defer cleanup()
        if @eq(1, 1) break
        continue
    }
    return
}
```

## 绑定和赋值

```do
// 局部变量绑定
value i32 = 1

// 局部不可变绑定
_limit i32 = 10

// 单目标赋值
value = 2

// 多目标赋值
a, b = pair()

// 丢弃第一个返回值
_, ok = check()
```

规则: `name Type = expr` 永远声明新绑定; 当前作用域或任何外层可见作用域里只要已经有同名绑定, 都不能再次写 typed bind, 必须改用 `name = expr` 赋值。局部声明也不能遮蔽外层局部绑定、函数参数、loop 绑定、模块级变量或顶层常量。

已有绑定可以使用没有 `else` 的条件重赋值. 条件为假时保留原值, 赋值表达式不会执行. 该形式不能用于创建新绑定.

```do
count i32 = 123
count = if b 128

pair Tuple<i32, bool> = if b .{1, true} else .{2, false}
pair = if b .{3, false}
```

条件重赋值支持 scalar 目标和元素均为 scalar slot 的 Tuple 目标. managed 或嵌套聚合目标暂未支持.

结构体字段初始化也可以使用带 `else` 的值 `if`, 包括可空字段:

```do
User{
    id i32 | nil
}

user = User{
    id = if has_auth(token) 123 else 0
}

user = User{
    id = if has_auth(token) 222 else nil
}
```

## List 条件元素语法预留

以下是后续 List 条件元素/展开语法的设计草案, 当前尚未实现. 无 `else` 的条件元素在条件为真时加入元素, 为假时跳过该项.

```do
nums = List<i32>{
    0,
    if b 111,
}
// b 为真: [0, 111]; b 为假: [0]

nums = List<i32>{
    0,
    if b {1} else {2},
    if b {1, 3, 5, 7, 9} else {2},
    if b {1, 3, 5, 7, 9} else 2,
    loop value, index = xs {
        print(value, index)
        value, index
    },
}
```
