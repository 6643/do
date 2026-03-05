// expr 语法设计总览(集中版)
// 使用类型: i32, i64, f64, bool, nil, Text, List, Map, Tuple, User
// 语法设计表达式: CallExpr, DoExpr, AsyncCtrlExpr, StructLit, ListLit, MapLit, TupleLit, BraceLit, Literal
//
// ## 7. 表达式与字面量
// Expr           := CallExpr
//                | DoExpr
//                | AsyncCtrlExpr
//                | LambdaExpr
//                | BraceLit
//                | StructLit
//                | ListLit
//                | MapLit
//                | TupleLit
//                | Ident
//                | Literal
//
// CallExpr       := Ident "(" Args? ")"
// Args           := Expr ("," Expr)* [","]
// DoExpr         := "do" CallExpr
// AsyncCtrlExpr  := DoneExpr | WaitExpr | WaitOneExpr | WaitAnyExpr | WaitAllExpr | CancelExpr | StatusExpr
// DoneExpr       := "done" "(" Expr ")"
// WaitExpr       := "wait" "(" Expr ["," Expr] ")"
// WaitOneExpr    := "wait_one" "(" Expr "," Expr ("," Expr)* [","] ")"
// WaitAnyExpr    := "wait_any" "(" Expr "," Expr ("," Expr)* [","] ")"
// WaitAllExpr    := "wait_all" "(" Expr "," Expr ("," Expr)* [","] ")"
// CancelExpr     := "cancel" "(" Expr ")"
// StatusExpr     := "status" "(" Expr ")"
// LambdaExpr     := "|" Params? "|" Expr
//
// BraceLit       := "{" BraceItems? "}"
// BraceItems     := ExprList | PairList
//
// StructLit      := TypeName "{" NamedArgs? "}"
// ListLit        := "List" "<" TypeExpr ">" "{" ExprList? "}"
// MapLit         := "Map" "<" TypeExpr "," TypeExpr ">" "{" PairList? "}"
// TupleLit       := "Tuple" "<" TypeList ">" "{" ExprList? "}"
//
// 集合字面量规则:
// 1. `List/Map/Tuple` 使用完整写法 `Type<...>{...}`.
// 2. 空集合写法固定为 `Type<...>{}`.
// 3. `BraceLit` 只支持纯 `ExprList` 或纯 `PairList`, 不支持混用.
//
// ----
// 可执行正向示例(当前实现可解析子集):

User {
    id i32
    name Text
}

work(a i32) i32 => a
to_i8(v i32) i8 => v
to_i64(v i32) i64 => v
to_f64(v i64) f64 => v

test "expr syntax design in one file" {
    // 1. CallExpr
    y = add(1, 2)

    // 2. DoExpr + AsyncCtrlExpr
    f1 = do work(1)
    f2 = do work(2)
    f3 = do work(3)
    done_flag = done(f1)
    out = wait(f1)
    out_t = wait(1000, f1)
    one = wait_one(1000, f1, f2, f3)
    any = wait_any(1000, f1, f2)
    all = wait_all(1000, f1, f2, f3)
    canceled = cancel(f2)
    st = status(f3)

    // 3. Struct/List/Map/Tuple/Brace 字面量
    u = User{id: 1, name: "tom"}
    xs = List<i32>{1, 2, 3}
    kv = Map<Text, i32>{"a": 1, "b": 2}
    empty_map = Map<i32, i32>{}
    t = Tuple<i32, Text>{1, "ok"}
    fields = {.name, .id}
    patch = {.name: "neo", .id: 2}
    u2 = set(u, patch)
    {name} = get(u2, {.name})

    // 4. Literal + convert calls
    ok = true
    none = nil
    i8_v = to_i8(1)
    i64_v = to_i64(2)
    f64_v = to_f64(i64_v)

    if y return
    if done_flag return
    if out return
    if out_t return
    if one return
    if any return
    if all return
    if canceled return
    if st return
    if u return
    if xs return
    if kv return
    if empty_map return
    if t return
    if fields return
    if patch return
    if u2 return
    if name return
    if ok return
    if i8_v return
    if i64_v return
    if f64_v return
    _ = none
}
