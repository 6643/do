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
    // defer 调用
    defer abc()

    // defer 块
    defer {
        print("defer")
    }

    return
}
```

`defer` 离开当前词法区域时执行。

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
