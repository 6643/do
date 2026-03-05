// tuple 语法设计总览(集中版)
// 使用类型: i32, Text, Tuple<i32, Text>
// 语法设计表达式: TupleLit, MultiReturnSpec, ReturnExprList, Assign.MultiReturn
//
// ## 7. 表达式与字面量
// TupleLit       := "Tuple" "<" TypeList ">" "{" ExprList? "}"
//
// ## 12.6 多返回值策略(与 tuple 关系)
// 1. 支持 Go 风格多返回值声明与接收.
// 2. 函数声明使用无括号返回列表: `f(...) T1, T2, ...`.
// 3. 返回语句支持 `return` 或 `return e1, e2, ...`.
// 4. 接收语句支持 `a, b, ... = f(...)`.
// 5. 多返回值与 `Tuple` 通过显式构造/解构转换.
//
// 设计示例(语法设计, 注释保真):
// pair() i32, Text => 1, "ok"
// a, b = pair()
// t = Tuple<i32, Text>{a, b}
//
// ----
// 可执行正向示例(当前实现可解析子集):

pair() i32, Text => 1, "ok"
id_tuple(x Tuple<i32, Text>) Tuple<i32, Text> => x

test "tuple syntax design in one file" {
    // 1. tuple 字面量
    t = Tuple<i32, Text>{1, "ok"}
    t2 = id_tuple(t)

    // 2. 多返回先接收, 再显式构造 tuple
    a, b = pair()
    t3 = Tuple<i32, Text>{a, b}

    print(t)
    print(t2)
    print(t3)

    if a return
    if b return
}
