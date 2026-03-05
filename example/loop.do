// loop 语法设计总览(集中版)
// 使用类型: i32, bool, List<i8>, Map<i32, i32>
// 语法设计表达式: LoopStmt, LoopCond, LoopBind, BreakStmt, ContinueStmt
//
// ### 6.3 loop 语句
// LoopStmt       := "loop" "{" [Label] Stmt* "}"
//                | "loop" LoopCond "{" Stmt* "}"
//                | "loop" LoopBind ":=" Expr "{" Stmt* "}"
// LoopCond       := Expr
// LoopBind       := Ident | Ident "," Ident
// Label          := "'" Ident
// BreakStmt      := "break" [Label]
// ContinueStmt   := "continue" [Label]
//
// 约束:
// 1. `loop cond {}` 的 `cond` 只要求结果为 `bool`.
// 2. `cond` 可为任意返回 `bool` 的表达式, 不限制函数参数个数.
//
// ### 12.8 loop 头部
// 1. `loop` 头部固定支持 3 类: `loop {}`, `loop cond {}`, `loop bind := iterable {}`.
// 2. `bind` 固定支持 `v` 或 `v, i` 两种形态.
// 3. `iterable` 位置支持标识符与调用表达式, 例如 `list_a`, `map_a`, `range(1, 10, 1)`.
// 4. 条件循环支持任意返回 `bool` 的表达式, 不限制函数参数个数.
// 5. 条件位谓词可按语义命名, 例如 `loop has(user_map, uid) { ... }`, `loop is_valid(user) { ... }`.
// 6. 标签语法沿用 `loop { 'outer ... }`, 与新头部写法并存.
//
// 设计示例(语法设计, 注释保真):
// 1. 基础块循环(Loop.Basic)
// loop {
//     if done(fid) break
//     tick()
// }
//
// 2. 条件循环(Loop.Cond)
// count = 0
// loop lt(count, 3) {
//     count = add(count, 1)
// }
//
// 3. 集合迭代-值与索引(Loop.IterListWithIndex)
// loop val, index := list_a {
//     print(val, index)
// }
//
// 4. 集合迭代-仅值(Loop.IterListValueOnly)
// loop val := list_a {
//     print(val)
// }
//
// 5. 映射迭代(Loop.IterMapKeyValue)
// loop key, val := map_a {
//     print(key, val)
// }
//
// 6. range 迭代(Loop.IterRange)
// loop i := range(1, 10, 1) {
//     print(i)
// }
//
// 7. 标签循环(Loop.LabelRightSide)
// loop { 'outer
//     loop {
//         if need_skip() continue
//         if need_exit() break 'outer
//         work()
//     }
// }
//
// ----
// 可执行正向示例(当前实现可解析子集):

User {
    id i32
}

is_valid(u User) bool => true
has(user_map i32, uid i32) bool => true

test "loop syntax design in one file" {
    // 1. 基础块循环
    loop {
        break
    }

    // 2. 条件循环
    count = 0
    loop lt(count, 3) {
        count = add(count, 1)
    }

    // 3. 条件循环谓词
    loop is_valid(User{id: 1}) {
        break
    }

    user_map = 1
    uid = 2
    loop has(user_map, uid) {
        break
    }

    // 4. 绑定迭代
    list_a = List<i8>{1, 2, 3}
    loop val, index := list_a {
        print(val, index)
    }
    loop val := list_a {
        print(val)
    }

    map_a = Map<i32, i32>{}
    loop key, val := map_a {
        print(key, val)
    }

    // 5. range 迭代
    loop i := range(1, 4, 1) {
        print(i)
    }
}
