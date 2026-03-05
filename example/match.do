// match 语法设计总览(集中版)
// 使用类型: i32, User, Book, Literal
// 语法设计表达式: MatchStmt, MatchArm, Pattern, PatternFields
//
// ## 9. match 规则
// MatchStmt      := "match" Expr "{" MatchArm* "}"
// MatchArm       := Pattern "=>" (Block | Stmt) [","]
// Pattern        := "_"
//                | TypeName "(" Ident ")"
//                | TypeName "{" PatternFields? "}"
//                | Literal
//
// PatternFields  := PatternField ("," PatternField)* [","]
// PatternField   := Ident
//
// 约束:
// 1. `match` 分支模式固定为 `_`/类型模式/字面量模式.
// 2. 复杂谓词放在分支体内部语句中.
// 3. `match` 作为语句节点使用.
// 4. 复杂条件放到分支语句内部处理.
// 5. `match` 目标位必须是单值表达式.
// 6. 多返回函数结果先接收再使用, `match` 目标位只接收单值.
// 7. 若函数返回多值, 必须先接收到变量后再 `match`.
//
// 设计示例(语法设计, 注释保真):
// match x {
//     User(u) => print(u),
//     Book{price} => {
//         if gt(price, 100) print("high")
//     },
//     0 => print("zero"),
//     _ => print("other"),
// }
//
// tag, payload = decode(msg)
// match tag {
//     0 => print("ok"),
//     _ => print("other"),
// }
//
// ----
// 可执行正向示例(当前实现可解析子集):

User {
    id i32
}

Book {
    price i32
}

make_user() User => User{id: 1}
make_book() Book => Book{price: 7}
pair(a i32, b i32) i32, i32 => a, b

test "match syntax design in one file" {
    // 1. 字面量模式 + 通配符
    x = 1
    match x {
        0 => return,
        1 => return,
        _ => return,
    }

    // 2. 类型绑定模式
    u = make_user()
    match u {
        User(v) => return,
        _ => return,
    }

    // 3. 结构字段模式
    b = make_book()
    match b {
        Book{price} => {
            if price return
        },
        _ => return,
    }

    // 4. 多返回先接收再 match(单值目标位)
    left, right = pair(1, 2)
    match left {
        _ => return,
    }
    if right return
}
