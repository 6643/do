# do 语言 WASM 运行时与 ARC 长期设计 (v5.1)

**版本**: 5.1 (Implicit ARC + Perceus + Acyclic Runtime Graph)
**核心目标**: 值语义不变, 运行时确定性释放, 低停顿, 面向 WASM 32 位环境, 最终不引入循环 GC
**状态**: 长期运行时草案, 仅作优化参考; v1 可实现内存模型以 `doc/memory.md` 为准, 需与 `doc/spec_rules.md` 同步校准。

> 本文保留 Implicit ARC、Perceus、Region、无环 runtime graph、header 压缩和未来并发方向。
> 当前实现不直接按本文全部落地; 先按 `doc/memory.md` 的 v1 边界实现 managed handle、ARC、`[T]`、`text` 和 host ABI 基础模型。

---

## 1. 约束与设计原则

1. 用户态不暴露引用与指针, 语言语义保持值传递。
2. 编译器在生命周期内隐式插入 `inc/dec`, 用户代码不写手工内存管理。
3. 以 Perceus/FBIP 为核心: `RC == 1` 时优先原地复用。
4. 单线程 WASM 先行, 并发场景后续增量支持。
5. 最终目标为不引入循环 GC, 运行时对象图必须保持无强环。

### 1.1 Swift ARC 借鉴边界

Do 的 ARC 只借鉴 Swift 的三个核心原则:

1. ARC 对用户透明: 源码层不出现 `retain/release/free`。
2. 值语义优先: inline scalar、enum、error、inline struct 不进入 ARC object。
3. COW 优化: `rc == 1` 时允许原地复用, `rc > 1` 时 clone 后写入。

Do v1 不照搬 Swift 的以下机制:

1. 不区分 class/reference type; Do 源码层没有 reference/pointer。
2. 不支持闭包捕获, 因此 v1 不需要 weak/unowned 来打破闭包或对象强环。
3. 不引入用户可见 deinit; 释放只按 `type_id -> layout table` 执行 managed 字段和元素的 `dec`。
4. 不引入复杂 runtime object header; v1 先保持统一 managed object 头和明确的 allocator block 结构。

---

## 2. v1 主线与长期分层候选

本节先记录当前 v1 主线, 再描述长期优化方向。v1 先实现 managed handle、对象头、layout table、ARC 插桩和 1KB block allocator; Region、header 压缩和并发状态属于后续优化。

### 2.1 v1 层次结构

1. **Stack/Inline 层**: 基础类型、函数符号、无受管字段的小结构体, 无 ARC 成本。
2. **ARC Heap 层**: `[T]`、`text`、含受管字段结构体、大结构体等 managed 对象。
3. **Runtime Graph 约束层**: 仅在后续引入 Future/Task/FFI 时约束其关系为无强环图。
4. **Region 层候选**: 表达式短生命周期对象 (函数内 arena), 作用域退出批量释放; 依赖 escape analysis, 不进入 v1。

### 2.2 v1 allocator 主线

1. Wasm memory grow 固定以 64KB page 为粒度。
2. Do allocator 在每个 page 内切成 64 个 1KB block。
3. `cap == 0` 表示 free span head, `cap == 1` 表示 large object span head, `cap > 1` 表示 small object block。
4. small block 使用 bitmap 表示 slot 占用状态。
5. large object 使用连续多个 1KB block span。
6. 同一 `slot_units` 的 `head_block/cursor_block` 放在外置 `SlotClassState`。

---

## 3. 生命周期插桩: 隐式 `inc/dec` 规则

以下规则由编译器在 IR 阶段自动插入:

### 3.1 赋值与覆盖

1. `a = b` 且 `b` 后续仍被使用: 先 `inc(b)`。
2. `a` 原有受管值: 在写入前 `dec(a_old)`。
3. 自赋值与别名路径必须先保护右值, 再释放左值。

### 3.2 函数调用与返回

1. 实参若调用后不再使用: 视为末次使用, 调用路径不插 `inc`。
2. 实参若调用后仍使用: 调用前 `inc`。
3. 返回值所有权转移给调用方, callee 不重复 `dec` 返回对象。

### 3.3 控制流

1. 分支合流点 (phi) 在边上做计数平衡, 避免合流点拍脑袋补偿。
2. 循环回边变量保证每轮净计数变化为 0。
3. `defer` / 早退路径统一进入清理块, 确保 `dec` 完整执行。

### 3.4 作用域清理

1. 局部变量离开作用域时统一 `dec`。
2. 非逃逸对象优先 region 回收, 避免进入 ARC heap。

---

## 4. 长期对象元数据压缩候选

`doc/memory.md` 的 v1 默认对象头是 `u32 rc + u32 type_id`。`len/cap` 不属于公共对象头, 而是放进 `text` / `[T]` 这类具体 payload。本节只比较后续 header 压缩候选, 不作为 v1 默认实现。

### 4.1 三套压缩配置

| 字段 | 配置 A | 配置 B | 配置 C |
| :--- | :--- | :--- | :--- |
| RC | u8 | u16 | u32 |
| type_id | u8 | u16 | u32 |
| Meta 总大小 | 2B | 4B | 8B |
| 目标场景 | 极限内存 | 默认平衡 | 并发/原子友好 |

### 4.2 推荐定位

配置 B (`u16/u16`) 可作为后续平衡压缩候选:

1. 比 A 更安全, 减少 RC/type_id 溢出风险。
2. 比 C 更省元数据。
3. 只有在 v1 header 的 benchmark 显示元数据成本成为主要瓶颈后, 才考虑切换。

### 4.3 溢出策略

1. 不采用“饱和即永生”。
2. RC 溢出写入 side table 扩展计数。
3. type_id 超出静态范围时通过模块级扩展映射表处理。
4. side table 不进入 v1, 避免把正确性闭环和压缩优化耦合在一起。

---

## 5. 运行时释放与复用

### 5.1 释放执行模型

1. `dec` 到 0 后进入释放队列。
2. 递归释放改为显式 worklist 迭代, 避免深结构栈溢出。
3. 根据 `type_id` 查询布局表, 对字段逐项 `dec`。

### 5.2 Perceus 复用

1. 写路径上检测 `RC == 1`。
2. 命中后执行原地更新, 避免 clone 与重复分配。
3. 复用失败再走常规 copy-on-write。

### 5.3 COW 与大小数据界分

1. 语义始终保持值传递, COW 仅是实现优化。
2. 小数据直接拷贝, 大数据走共享 + 写时复制。
3. 初始阈值采用 `64B` (一个 cache line), 后续按基准测试调优。

**建议判定规则**

1. 基础类型 (`i32/u32/f64/bool`) 永远按小数据处理。
2. 含受管字段 (`[u8]/List/HashMap/...`) 的结构按大数据处理。
3. 不含受管字段且静态大小 `<= 64B` 的结构按小数据处理。
4. 不含受管字段且静态大小 `> 64B` 的结构按大数据处理。

**写路径规则**

1. 大数据写入时若 `RC == 1`, 原地修改。
2. 大数据写入时若 `RC > 1`, clone 后修改。
3. 小数据写入直接覆盖, 不进入 COW 分支。

**伪代码**

```text
if is_primitive(type):
  copy
else if has_managed_field(type):
  share_handle_and_cow
else if static_size(type) <= 64:
  copy
else:
  share_handle_and_cow
```

**特殊边界限制**

1. 写频很高的数据结构不应长期维持共享形态, 编译器应优先触发末次使用优化与唯一性优化, 降低重复 clone 成本。
2. 读多写少的数据结构优先保持共享 + COW, 以降低传参与返回时的复制成本。
3. FFI 边界默认保守策略: 跨宿主可变内存优先复制, 禁止将可变共享缓冲直接暴露给宿主。

---

## 6. Future/Task/FFI 去环约束 (后续预留, 无循环 GC 前提)

### 6.1 核心约束

1. Task 与 Future 之间禁止双向强引用。
2. 等待关系统一使用 ID (`task_id` / `future_id`), 不直接持有对象强引用。
3. FFI 回调注册使用 token/ID, 不反向强持有语言对象。
4. 外部资源 (fd/socket/handle) 必须显式 `close`, `drop` 仅作兜底。
5. 若未来支持捕获闭包, 闭包环境必须显式纳入 managed 对象图, 并禁止 callback registry 与闭包环境形成强引用环。

### 6.2 推荐对象关系

1. `Future.waiters`: `List<TaskId>`。
2. `Task.awaiting`: `FutureId | nil`。
3. `Task.joiners`: `List<TaskId>`。
4. `FfiHandle`: `{host_id, close_fn, closed}`。

### 6.3 运行时校验

1. Debug 模式启用无环断言: 调度器图检测到强环立即报错。
2. Release 模式保留轻量计数校验, 禁止引入回边强引用。
3. CI 中加入 Future/Task/FFI 图完整性测试, 作为发布门禁。

---

## 7. 编译优化与成本控制

1. `inc` 后紧邻 `dec` 相消。
2. 内联后再次执行 ARC 冗余消除。
3. 批量 `dec` 提交减少热点抖动。
4. 对纯基础类型路径完全不生成 ARC 指令。

---

## 8. 关键边界测试

1. **覆盖写安全**: `a = b` 且 `a`/`b` 别名同源。
2. **深链释放**: 万级深度 List/Tree 不应栈溢出。
3. **无环约束**: 构造 Task/Future/FFI 组合, 验证不存在强环并可被 ARC 回收。
4. **溢出计数**: 人工压测 RC 达上限后 side table 正常回落。
5. **分支合流**: 多分支返回同一对象不泄漏不重释放。
6. **早退路径**: `return` + `defer` 混合路径计数平衡。

---

## 9. 实施顺序

1. 先按 `doc/memory.md` 完成 v1 managed handle、对象头、layout table、`inc/dec` 和 release worklist。
2. 接入 ARC 指令相消与末次使用优化。
3. 打通 `RC == 1` 复用路径。
4. 基于 benchmark 决定是否引入更多 size class、header 压缩或 region 优化。
5. 再评估 non-escape 下沉到 region。
6. 最后接入无环图校验与调试检测, 不实现 cycle collector。

---

## 10. 未来状态化 header 候选

| 状态 | RC 模式 | 存储位置 | 核心优势 |
| --- | --- | --- | --- |
| 不可变 (Const) | 忽略或饱和计数 | 共享片 / 静态区 | 读性能最高, 多线程无锁 |
| 单主态 (Unique) | 无 RC | 局部片 | 零元数据开销, 原地修改 |
| 线程内 (Local) | 1B RC (尾部) | 局部片 | 灵活的局部 COW |
| 跨线程 (Shared) | 4B RC (尾部) | 共享片 | 安全的跨 Worker 协作 |

状态化 header 只作为未来并发与 header 压缩方向, 不进入 v1 或第一轮 ARC 实现。
