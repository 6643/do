# do 语言异步语义规范 (v0.1)

## 1. 目标

1. 采用无色异步: 函数签名不区分 async/sync。
2. 显式并发控制: 仅 `do` 创建任务。
3. 显式控制面: 仅通过 Future 句柄做等待、取消、重试。
4. 最终保持无环运行时图, 不引入循环 GC。

---

## 2. 核心语义

### 2.1 调用语义

1. `f(args...)`: 当前任务内同步执行, 不创建 Task。
2. `do f(args...)`: 创建新 Task 并返回 `Future<T>`。
3. `do` 是并发入口关键字, 不允许其他隐式并发入口。

### 2.2 Future 控制语义

1. `done(f)`: 等待 `f` 进入终态并返回结果。
2. `any_done(f1, f2, ...)`: 返回首个完成的 Future 结果。
3. `all_done(f1, f2, ...)`: 等待全部完成并返回结果集合。
4. `cancel(f...)`: 发起协作取消请求, 不做强制杀死。
5. `retry(f...)`: 基于原调用参数重建 Task, 返回新 Future。
6. `set_timeout(f, ms)`: 为 Future 设置截止时间。

### 2.3 取消与重试约束

1. 取消生效点仅在挂起点/调度点检查。
2. `retry` 不复用已终态 Future, 必须返回新 FutureId。
3. `done` 只等待, 不隐式触发重试。

---

## 3. Task 与 Future 关系

1. `Task` 是执行单元, `Future` 是结果槽。
2. 建议关系: `1 Task -> 1 Future`, `1 Future -> N waiters`。
3. 运行时关联使用 ID, 不使用双向强引用:
4. `Task.awaiting = FutureId | nil`
5. `Future.waiters = List<TaskId>`
6. 调度器队列持有 `TaskId`, Future 表持有 `FutureId`。

---

## 4. 单线程异步模型

### 4.1 可行性

1. 单线程可以实现异步。
2. 核心条件是协作调度: `suspend/resume + event loop + non-blocking host api`。
3. 该模型消除用户侧线程心智, 但不等于底层平台永远无线程。

### 4.2 必要约束

1. 任何阻塞式 FFI 不得直接在调度线程执行。
2. 所有外部 I/O 必须经非阻塞接口或回调通知恢复。
3. 调度器每轮推进就绪队列和超时队列。

---

## 5. 是否可完全不依赖运行时

1. 纯计算协程切换可由编译器 + 语言运行时本地完成。
2. 真实 I/O 异步不能脱离宿主能力, 必须依赖运行时/宿主事件源。
3. 结论: 可以最小化运行时依赖, 但不能在 I/O 场景下完全去运行时。

---

## 6. 与 GC 约束对齐

1. Future/Task/FFI 必须遵守无环图规则。
2. FFI 资源显式 `close`, `drop` 仅兜底。
3. Debug 模式开启无环断言, CI 校验图完整性。

---

## 7. 参考示例映射

对应 `do/spec/future.do`:

1. `a = do login(cx, 1, "token")`: 创建 Task + Future。
2. `set_timeout(a, 1000)`: 注册超时。
3. `cancel(a)`: 发起取消。
4. `a2 = retry(a)`: 生成新 Future。
5. `{x, y, z} = all_done(a, b, c)`: 聚合等待。

