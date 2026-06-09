# 表达式

## 字面量

```do
1       // 整数字面量
3.14    // 浮点字面量
"hello" // 字符串字面量
true    // bool true
false   // bool false
nil     // nil 字面量
```

## 行字符串

```do
// 行字符串绑定
message text =
    \\hello
    \\world
```

## 名字

```do
value        // 普通值名
_limit       // 只读值名
OrderCreated // 枚举分支值名
```

## 括号

```do
(value)      // 普通括号表达式
(@add(a, b)) // 内建调用括号表达式
```

## 调用

```do
ready()           // 无参数调用
add(1, 2)         // 固定参数调用
sum(1, 2, 3)      // 多实参调用
sum(1, ...items)  // 固定实参加 spread 实参
collect(...items) // 纯 spread 实参调用
```

## lambda

```do
run(() -> nil {
    return
}) // 无参数 block lambda 实参

map(items, (value i32) -> i32 {
    return @add(value, 1)
}) // 带类型参数的 block lambda 实参

map(items, (value i32) -> i32 => @add(value, 1)) // 带类型参数的表达式体 lambda 实参

state = @set(state, .count, (value) => @add(value, 1)) // 推导参数类型的 lambda 更新值
```

## 聚合

```do
User{}                         // 空 typed 聚合
User{id = 1, name = "tom"}      // typed 字段聚合
User{id = 1, name = "tom",}     // typed 字段聚合带尾逗号

.{}                     // 空推导聚合
.{1, 2, 3}              // 推导元素聚合
.{id = 1, name = "tom"} // 推导字段聚合
```

## 表达式语句

```do
ready()      // 无参数调用语句
log("done")  // 带参数调用语句
```
