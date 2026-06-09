# 枚举

## 值枚举

```do
OrderStatus i32 = OrderCreated(1) | OrderPaid(2) | OrderClosed(3) // i32 承载值枚举

ByteKind u8 = ByteSpace(1) | ByteDigit(2) | ByteLetter(3) // u8 承载值枚举
```

## 私有值枚举

```do
.InternalStatus u8 = Ready(1) | .Hidden(2) // private 值枚举

status InternalStatus = Ready  // public 分支值绑定
hidden InternalStatus = Hidden // private 分支值绑定时使用实际名
```

## 枚举值使用

```do
status OrderStatus = OrderCreated // 枚举值绑定

is_paid(status OrderStatus) -> bool {
    return @eq(status, OrderPaid) // 枚举值比较
}
```
