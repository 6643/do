# A + G6.2 + D2 下一阶段设计

**状态:** 设计已确认，待实施计划
**日期:** 2026-08-05

## 1. 目标

下一阶段由三个相互独立、可分别验收的闭环组成：

1. **A：Result 政策收口**：普通 Do API 统一使用 `T | E`；WIT/Component 内部继续使用 tag + payload 的 Result ABI。
2. **G6.2：剩余有界能力**：每次只增加一个有 pinned probe 支撑的 producer/resource shape，保持未知 shape 显式拒绝。
3. **D2：真实 Host Runtime smoke**：让已经完成 lowering 的 Component 由 Rust/Wasmtime 对真实本机资源执行，逐步恢复后置 skip。

这不是一次完整 WASI 实现，也不是一次公开 ownership 语法发布。每个 shape 和每个 host 资源类别都必须有独立的 design、测试和 runtime 证据。

## 2. 当前基线

仓库当前已验证：

- 普通标准库和 WASI wrapper 已从 `Result<T, E>` 迁移到 `T | E`。
- 内部 private Result probe、resource Result、HTTP payload error/cancellation slices 已有 Component/Rust/Wasmtime 证据。
- G6.2 generic consumer、multi-owned resource、多个 nested-owned path、bounded producer、StreamMirror 和相关 ownership invariant 已闭环。
- `variant-resource-stream` 的 private `ticket/idle/failed` slice 已进入 registry 并通过 compiler-generated Component/Rust/Wasmtime gate；后续 G6.2 shape 仍须另立 pinned probe 与独立 gate。
- 当前 pinned `wasm-tools` 对含 `borrow<T>` 的 stream record 仍拒绝；公开 `own<T>/borrow<T>/ref<T>` 不在本阶段范围。
- 当前真实 runtime 证据主要是受控 host adapter；这不能替代真实 file/dir/stream/socket/http smoke。

权威状态文件为 `doc/start_here.md`、`doc/pending_blocked.md`、`doc/host_abi_blockers.md` 和 `doc/master_plan.md`。

## 3. 主线 A：Result 政策收口

### 3.1 语义边界

- 普通 Do 源码使用 `T | E` 表达成功值或错误值。
- `Result<T, E>` 只作为内部 WIT/Component/ABI 的 tag + payload 形态，或作为 private probe 的内部构造。
- 不增加 Go 式 `a() -> T, Error` 多返回错误协议；Do 没有零值错误语义。
- 普通 union 不允许重复分支；`T | T` 保持负例。
- 内部 `Result<T, T>` 可以用于 ABI/probe 验证，但不能成为普通 Do API 的推荐写法。

### 3.2 实施边界

1. 扫描 `lib/`、WASI registry、示例、spec 和计划文档，确认普通 API 没有残留 `Result<T, E>`。
2. 保留内部 Component lowering 的 result tag、payload、resource transfer/drop 和 immediate/pending 状态处理。
3. 保留 `T | E` 正例、普通重复 union 负例和 private Result probe。
4. 同步 `doc/spec_rules.md`、WIT lowering 文档、Result 设计/迁移文档和接手入口。

### 3.3 验收

- `zig test main.zig` 和 `./src/build/test/run_tests.sh` 通过。
- Result 相关 compile/test fixtures 通过，未知或不支持 lowering 仍得到明确诊断。
- 已登记 Component 的 Rust/Wasmtime gate 保持 pending/ready/error/cancel/cleanup 结果不变。

## 4. 主线 G6.2：剩余有界能力

### 4.1 V1 首个 shape

第一项是把已有 canonical probe 注册为 private descriptor lowering：

```wit
variant event {
  ticket(own<ticket>),
  idle,
  failed(error-code),
}
```

`read-via-stream` 只允许一次 stream read、一个 event、一个 completion future 和一个 owned ticket。`idle` 与 `failed` 分支不得触发 ticket drop；`ticket` 分支转移到 frame-owned slot 后只能由统一 cleanup helper 释放。

V1 必须复用 probe 已经测得的布局和行为，而不是从其他 resource/list probe 推断 ABI：tag 位于 result buffer 起点，payload 位于后续槽位，invalid tag 必须在 ownership transfer 前 trap。

### 4.2 后续 shape 选择

V1 全绿后才选择下一项，优先级为：

1. 有 pinned evidence 的 payload-bearing completion error；
2. 第二个独立的 list/resource shape；
3. 其他能在单次调用和有限终态内证明 ownership 的 producer shape。

每一项必须单独保存 design 和 stop condition，不能以“提高 forwarding/nesting 上限”作为能力目标。

### 4.3 保持拒绝的边界

- 任意 producer expression、任意 async-call composition 暂不放开。
- `borrow<T>` 在 pinned toolchain 明确拒绝时保持拒绝，不通过源码别名或特殊分支绕过。
- 第六跳 forwarding、第七层或更一般 nested resource 不作为本阶段的上限扩展。
- 未登记 descriptor、未知 variant tag、布局不明或无法证明 exactly-once cleanup 的 shape 必须显式失败。

### 4.4 每个 G6.2 shape 的 gate

1. design/spec 与 pinned WIT/WAT probe；
2. registry/manifest 只记录已测量的布局；
3. Do 正例与负例；
4. Core WAT marker 和 Component `parse/embed/new/validate`；
5. Rust/Wasmtime pending、ready、error、cancel/early-drop 矩阵；
6. `ResourceTable`、stream/future/resource drop 的 exactly-once 断言；
7. 全量回归和边界文档同步。

registry 只有在第 5、6 项全部通过后才允许新增条目。

## 5. 主线 D2：真实 Host Runtime smoke

### 5.1 运行时契约

- Rust/Wasmtime 使用一个 Component、一个 Store 和项目已有的 drive loop 规则。
- host adapter 不改变 Do ABI，不替编译器推断未知 WIT shape。
- 测试资源必须是本机可控、可清理的资源；禁止依赖外部网络或共享用户目录。
- 取消只结束 task/future，不回滚已发出的外部副作用；这与当前 WASI 对齐语义一致。

### 5.2 执行顺序

1. **filesystem**：临时目录和真实文件，覆盖 preopen、open、read/write、sync、read-directory、错误和 descriptor drop。
2. **stream**：真实 stdin/stdout 或 OS pipe，覆盖 pending、ready、EOF、host error 和 drop。
3. **socket**：loopback 临时端口，先只验证已支持的 create/bind/drop；不提前实现 listen/connect/accept/stream I/O。
4. **http**：本机 loopback server，覆盖已有 request/response、payload error 和 cancellation；不访问外部网络。

### 5.3 D2 gate

每个资源类别都必须证明：

- Do 生成的 Core WAT 可转换并组装成 Component；
- pinned WIT/wasm-tools 版本和 hash 被检查；
- Rust/Wasmtime 真实 host 行为与 Do 结果一致；
- pending/ready/error/cancel/early-drop 的 poll、drop、ownership 数量精确；
- 测试结束时 `ResourceTable` 为空，临时目录、socket、pipe 和子进程均已清理。

只有对应 gate 通过后，才恢复 `16_loop_recv_value`、`96_file_lib_resource_shape` 或 `118_wasi_p3_std_wrappers` 中与该资源类别相关的后置路径。

## 6. 统一验证与停止协议

### 6.1 证据层级

每个最小任务必须依次提供：

1. Zig/Do 前端测试；
2. WAT marker、registry/manifest 输出；
3. Component assembly/validation；
4. Rust/Wasmtime runtime matrix；
5. `run_tests.sh`，必要时 `RUN_WASM=1` 和 `run_release_smoke.sh`。

单独的 Core GC、generic async 或 hand-written WAT probe 不能被描述为完整 P3/WASI 完成。

### 6.2 停止条件

遇到以下任一条件，停止当前 shape，不扩大修改范围：

- pinned toolchain 拒绝 WIT shape；
- canonical tag/payload/layout 无法稳定测量；
- ownership transfer 或 drop 次数不一致；
- invalid tag 在 ownership transfer 前未 trap；
- 单 Store 重入或 host drive 规则无法成立；
- 真实 OS 资源清理不可重复验证。

停止时把证据、恢复条件和是否可跳过写入 `doc/pending_blocked.md`；A、G6.2 其他 shape 和 D2 其他资源类别继续独立推进。

### 6.3 可回退边界

新 probe、负例和文档可以独立保留；新的 registry/descriptor 只有 runtime gate 全绿后才启用。这样某个 shape 失败时不会改变已发布能力，也不会要求删除已验证的 probe。

## 7. 非目标

本阶段不做：

- 公开 `own<T>`、`borrow<T>`、`ref<T>` 语法；
- 通用 Future/Stream scheduler 或任意 async-call lowering；
- 完整生成式 WIT world manifest；
- 完整 WASI 兼容性声明；
- 完整 ownership IR、跨函数唯一性证明、region/escape analysis；
- 外部网络 host smoke、生产资源写入或不可回滚的环境变更。

## 8. 交付文档

每个闭环完成后同步：

- `doc/start_here.md` 的停点和验证入口；
- `doc/pending_blocked.md` 的剩余边界；
- `doc/master_plan.md` / `doc/roadmap_status.md` 的状态；
- 相关 `doc/spec_rules.md`、WIT lowering 文档和 `CHANGELOG.md`。

本设计不授权直接实现；下一步是根据本 spec 生成独立、可执行的实施计划。
