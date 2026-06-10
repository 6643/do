# 循环

规则: build lowering 覆盖无限循环、标签跳转、guard `break/continue`、集合循环、字段反射循环和当前 `[T]` storage-backed 消费循环。标签只绑定紧随其后的 `loop`; `break #label` 和 `continue #label` 只能跳转到可见 loop label。集合循环源必须是 `[T]` 或后续明确声明的 collection type; `text` 不作为集合循环源, 需要显式转换为 `[u8]` 或通过文本库遍历。`recv(...)` 是消费循环专用形态, 不是普通函数调用; `fields(TypeOrTypeParam)` 是字段反射循环专用形态, 不是普通函数调用; 真实 channel/stream receive ABI 后续单独扩展。

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
// 当前 build lowering: 从 [T] source 按顺序接收值
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

规则: `recv(ch)` 只能出现在消费循环头部, 不能作为普通函数调用出现在赋值右侧、调用实参或返回值位置。

## 字段反射循环

```do
// 按 User 的可见字段做编译期展开
loop field = fields(User) {
    name text = @field_name(field)
    index usize = @field_index(field)
    has_default bool = @field_has_default(field)
}

// 泛型函数实例内按 T 绑定到的具体结构体展开
#T
field_count(value T) -> usize {
    count usize = 0
    loop field = fields(T) {
        count = @add(count, 1)
    }
    return count
}
```

规则: `fields(TypeOrTypeParam)` 只能出现在字段反射循环头部。`TypeOrTypeParam` 只能是具体结构体名, 或泛型函数中已实例化为具体结构体的单个类型参数名; 不接收 `Box<T>`、`[T]` 或 union 类型表达式。循环绑定是编译器字段元数据, 只能交给 `@field_name/@field_index/@field_has_default/@field_get/@field_set` 使用。

## 标签

```do
// 外层循环标签
#outer
loop {
    // 内层循环标签
    #inner
    loop {
        // 跳出外层标签
        if done break #outer

        // 继续内层标签
        if skip continue #inner

        // 跳出当前循环
        break
    }
}
```

## break 和 continue

```do
// 跳出当前循环
break

// 继续当前循环
continue

// 跳出指定标签循环
break #outer

// 继续指定标签循环
continue #outer
```

## 条件循环写法

```do
// 条件由 guard break 表达
loop {
    if @not(keep_running()) break
    step()
}
```
