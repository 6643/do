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
if ready return          // guard return
if ready return value    // guard 单值 return
if ready return a, b     // guard 多值 return
if done break            // guard break
if skip continue         // guard continue
if done break #outer     // guard 带标签 break
if skip continue #outer  // guard 带标签 continue
```

## return

```do
return       // nil return
return value // 单值 return
return a, b  // 多值 return
```

## defer

```do
// defer 调用目标函数
abc() -> nil {
    return
}

work() -> nil {
    defer abc() // defer 调用

    defer {
        print("defer") // defer 块
    }

    return
}
```

`defer` 离开当前词法区域时执行。

## 绑定和赋值

```do
value i32 = 1  // 局部变量绑定
_limit i32 = 10 // 局部不可变绑定

value = 2     // 单目标赋值
a, b = pair() // 多目标赋值
_, ok = check() // 丢弃第一个返回值
```
