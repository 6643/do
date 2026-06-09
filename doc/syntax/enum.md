# 枚举

## 值枚举

```do
// i32 承载值枚举
OrderStatus i32 = OrderCreated(1) | OrderPaid(2) | OrderClosed(3)

// u8 承载值枚举
ByteKind u8 = ByteSpace(1) | ByteDigit(2) | ByteLetter(3)
```

## 私有值枚举

```do
// private 值枚举
.InternalStatus u8 = Ready(1) | .Hidden(2)

// public 分支值绑定
status InternalStatus = Ready

// private 分支值绑定时使用实际名
hidden InternalStatus = Hidden
```

## 枚举值使用

```do
// 枚举值绑定
status OrderStatus = OrderCreated

is_paid(status OrderStatus) -> bool {
    // 枚举值比较
    return @eq(status, OrderPaid)
}
```
