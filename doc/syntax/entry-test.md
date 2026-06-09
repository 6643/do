# 入口和测试

## 入口

```do
// 程序入口
start() {
    return
}
```

## 测试

```do
// 空测试声明
test "name" {
    return
}

// 带局部绑定和 guard 的测试声明
test "value check" {
    value i32 = 1
    if @eq(value, 1) return
    return
}
```
