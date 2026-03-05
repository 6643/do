// async 语法设计总览(集中版)
// 使用类型: Future, i32, bool, List<T>
// 语法设计表达式: DoExpr, DoneExpr, WaitExpr, WaitOneExpr, WaitAnyExpr, WaitAllExpr, CancelExpr, StatusExpr
//
// ### 7.1 并发入口约束
// 固定写法:
// a = do fetch_user(1)
//
// 语义:
// 1. `f(args...)` 在当前执行流内同步执行, 返回普通结果.
// 2. `do f(args...)` 创建异步执行单元并返回 `Future<T>`.
// 3. 并发入口固定为 `do f(args...)`.
//
// ### 7.2 Future 控制语法
// 规则:
// 1. `done(f) -> bool`: 查询 Future 是否终态.
// 2. `wait(f) -> T | Error`: 等待 Future 完成并返回结果.
// 3. `wait(ms, f) -> T | Timeout | Error`: 带超时等待结果.
// 4. `wait_one(ms, f1, f2, ..., fn) -> T | Timeout | Error`: 等待多个 Future 中首个完成结果.
// 5. `wait_any(ms, f1, f2, ..., fn) -> T | Timeout | Error`: 等待多个 Future 中任意一个完成结果.
// 6. `wait_all(ms, f1, f2, ..., fn) -> List<T> | Timeout | Error`: 等待多个 Future 全部完成结果.
// 7. `cancel(f) -> bool`: 发起协作取消请求, 幂等.
// 8. `status(f) -> Pending | Running | Done | Canceled | Failed`: 查询 Future 状态.
//
// 约束:
// 1. 内建控制面函数集合固定为 `done/wait/wait_one/wait_any/wait_all/cancel/status`.
// 2. `wait` 参数个数固定为 `1` 或 `2`; `2` 参数形态的第 1 个参数为超时值.
// 3. `wait_one/wait_any/wait_all` 至少接收 `2` 个参数, 第 1 个参数为超时值.
// 4. 允许声明同名普通函数; 当存在同名且签名可匹配的普通函数时, 按普通函数解析.
// 5. 无同名可匹配普通函数时, 内建签名固定为:
//    `done(f)`, `wait(f)|wait(ms,f)`, `wait_one/any/all(ms,f1,...,fn)`, `cancel(f)`, `status(f)`.
//
// ### 12.3 异步控制面
// 1. 外部最小控制面: `done/wait/wait_one/wait_any/wait_all/cancel/status`.
// 2. 取消为幂等信号, 在任务安全点生效.
// 3. 取消后必须执行 `defer` 清理.
// 4. 所有控制面统一作用于 `Future`.
//
// ----
// 可执行正向示例(当前实现可解析子集):

work(a i32) i32 => a

test "async syntax design in one file" {
    f1 = do work(1)
    f2 = do work(2)
    f3 = do work(3)

    ready = done(f1)
    out = wait(f1)
    out_t = wait(1000, f1)
    one = wait_one(1000, f1, f2, f3)
    any = wait_any(1000, f1, f2)
    all = wait_all(1000, f1, f2, f3)
    canceled = cancel(f2)
    st = status(f3)

    if ready return
    if out return
    if out_t return
    if one return
    if any return
    if all return
    if canceled return
    if st return
}
