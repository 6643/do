// if 语法设计总览(集中版)
// 使用类型: bool, i32, User
// 语法设计表达式: IfStmt, IfTypePattern, ReturnStmt, CallExpr
//
// ### 6.2 if 语句
// IfStmt         := "if" Expr Block ["else" Block]
//                | "if" IfTypePattern ":=" Expr Block ["else" Block]
//                | "if" Expr Stmt
// IfTypePattern  := TypeName "(" Ident ")"
//                | TypeName "{" PatternFields? "}"
//
// 约束:
// 1. `if` 条件位必须是单值表达式.
// 2. 多返回函数结果先接收再使用, `if` 条件位只接收单值.
// 3. 若函数返回多值, 必须先接收到变量后再在 `if` 中使用.
// 4. `if P := expr` 的 `P` 仅允许类型模式(`Type(...)` 或 `Type{...}`).
// 5. `if P := expr` 的 `expr` 必须是单值表达式, `f_multi(...)` 直接使用为编译错误.
//
// 设计示例(语法设计, 注释保真):
// 1. 条件分支-块体(If.ExprBlock)
// if gt(age, 18) {
//     print("adult")
// } else {
//     print("minor")
// }
//
// 2. 模式绑定分支(If.PatternBind)
// if User{age} := item {
//     print(age)
// }
//
// 3. 单行短路分支(If.OneLine)
// if is_ok(x) return x
//
// 4. 多返回先接收再判断(If.MultiReturnBindThenUse)
// ok, code = check_auth(user)
// if ok {
//     print(code)
// }
//
// ----
// 可执行正向示例(当前实现可解析子集):

User {
    age i32
}

always_true() bool => true
is_ok(x i32) bool => true
check_auth(u User) bool, i32 => true, 200

test "if syntax design in one file" {
    age = 18
    if age {
        x = 1
        if x return
    } else {
        return
    }

    item = User{age: 20}
    if User{age} := item {
        if age return
    }

    x = 7
    if is_ok(x) return

    ok, code = check_auth(item)
    if ok {
        if code return
    }

    if always_true() return
}
