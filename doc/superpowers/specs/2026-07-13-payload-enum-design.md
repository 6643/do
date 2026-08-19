# Design: Payload Enum (L1 only)

**Status:** Approved  
**Syntax (locked):**

```do
Message = Quit | Text([u8]) | Binary([u8]) | TcpAddr(IpSocketAddress)
```

## Family

| Kind | Form |
|------|------|
| Error enum | `FileError error = A \| B` |
| Value enum | `Color i32 = Red(0) \| Green(1)` |
| **Payload enum** | **`Message = Quit \| Text([u8]) \| …`** |

## Rules

1. **Not a type alias / not a flat union name.** Declares a tagged enum type.
2. **Disambiguation** for top-level `TypeName =`:
   - RHS starts with `@` → wasi/lib (existing)
   - second token `error` → error enum
   - second token base int carrier → value enum
   - RHS is `Case (| Case)*` where `Case = Ident | Ident(TypeExpr)` → **payload enum**
3. **No L2/L3:** no bare `i32`/`bool` arms, no `i32(2)`, no string literal types.
4. **No mixing** `Red(0)` constant parens with `Text([u8])` type parens in one decl.
5. **Construct:** unit `Quit`; payload `Text(buf)` with `buf : [u8]`. Whole expr type = enum type.
6. **Discriminate:** `@is(m, Text)` means case `Text`; on true, value narrows to payload type (unit → no payload).
7. **Lowering:** tag `i32` + max payload slots (same spirit as `UnionLayout`, tags = case order).
8. Case names: valid TypeName-style idents; must not collide with other cases in the enum; should not collide with same-module type names (v1: reject collision).

## Non-goals (v1)

- `match` sugar, generics on enum, multi-payload `Case(A,B)`, private case polish beyond existing patterns
- G6.3 dependency (optional later use for `IpSocketAddress`)
