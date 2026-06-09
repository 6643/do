# 循环

规则: build lowering 覆盖无限循环、标签跳转、guard `break/continue`、集合循环和消费循环。标签只绑定紧随其后的 `loop`; `break #label` 和 `continue #label` 只能跳转到可见 loop label。集合循环源必须是 `[T]` 或后续明确声明的 collection type; `text` 不作为集合循环源, 需要显式转换为 `[u8]` 或通过文本库遍历。

## 无限循环

```do
// 无限循环
loop {
    if done break
}
```

## 集合循环

```do
// 值和索引绑定
loop value, index = items {
    use(value, index)
}

// 丢弃索引
loop value, _ = items {
    use(value)
}

// 丢弃值
loop _, index = items {
    use_index(index)
}

// 同时丢弃值和索引
loop _, _ = items {
    tick()
}
```

## 消费循环

```do
// 接收值循环
loop value = recv(ch) {
    use(value)
}

// 接收值和计数循环
loop value, count = recv(ch) {
    use(value, count)
}

// 无错误接收源: 丢弃接收值, 保留计数
loop _, count = recv(ch) {
    use_count(count)
}
```

## 标签

```do
// 外层循环标签
#outer
loop {
    // 内层循环标签
    #inner
    loop {
        if done break #outer     // 跳出外层标签
        if skip continue #inner  // 继续内层标签
        break                    // 跳出当前循环
    }
}
```

## break 和 continue

```do
break           // 跳出当前循环
continue        // 继续当前循环
break #outer    // 跳出指定标签循环
continue #outer // 继续指定标签循环
```

## 条件循环写法

```do
// 条件由 guard break 表达
loop {
    if @not(keep_running()) break
    step()
}
```
