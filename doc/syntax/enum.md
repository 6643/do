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

规则: `value enum` 的分支值用 `@eq/@ne` 比较; `@is` 只做类型判断, 不用于分支值匹配。

## 载荷枚举

```do
// 具名 case；可选类型载荷（括号内是类型，不是值枚举常量）
Message = Quit | Text([u8]) | Binary([u8]) | TcpAddr(IpSocketAddress)
```

```do
// 构造：无载荷直接写 case 名；有载荷写 Case(expr)
m Message = Quit
b [u8] = "hi"
m = Text(b)
m = Binary(b)

// 判别与收窄：@is 第二参为 case 名；true 时 m 收窄为载荷类型
if @is(m, Text) {
    x [u8] = m
    _ = x
}
```

规则:

- 声明头是 `TypeName = Case (| Case)*`，**不是**类型别名，也不是平铺联合命名。
- `Case` 为 `Ident`（无载荷）或 `Ident(TypeExpr)`（载荷类型）。
- 与值枚举区分：值枚举声明为 `Name Carrier = Case(常量)`；载荷枚举括号内是类型。
- 同一声明内禁止混用常量括号与类型括号。
- `Text([u8])` 与 `Binary([u8])` 靠 **case 名 / tag** 区分，不靠载荷类型 alone。
- 不支持裸类型臂（`i32` / `bool`）与值约束臂（`i32(2)`）。

## 载荷枚举 (payload enum, L1)

```do
// 无载体类型: 声明 tagged enum, 不是 type alias / flat union
Message = Quit | Text([u8]) | Binary([u8])

start() {
    m Message = Quit
    b [u8] = "hi"
    m = Text(b)
    if @is(m, Text) {
        x [u8] = m
        _ = x
    }
    m = Binary(b)
    _ = m
    return
}
```

规则:
- 形式 `TypeName = Case (| Case)*`, 其中 `Case = Ident | Ident(TypeExpr)`
- 与 `Name error = …` (error enum) 和 `Name i32 = Red(0) | …` (value enum) 区分
- 不允许混用 `Red(0)` 常量括号与 `Text([u8])` 类型括号
- 构造: 单元 `Quit`; 载荷 `Text(buf)`; 整体类型为枚举类型
- 判别: `@is(m, Text)` 按 **case 名** 比 tag (Text 与 Binary 载荷类型同为 `[u8]` 也必须不同 case)
- 收窄后 `m` 的有效类型为该 case 的载荷类型 (单元 case 无载荷)
- 布局: `i32` tag + 最大载荷槽 (与 union 精神一致; `[u8]` 为 i32 句柄)
- L1 不包含: 裸 `i32`/`bool` 臂, `i32(2)`, `match` 糖, 多载荷 `Case(A,B)`
