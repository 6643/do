# 近期自动方案选择统计（排除人工裁定）

更新时间：2026-08-04
范围：2026-07-27 至 2026-08-04，仓库 `/home/_/._/do` 相关工作记录

状态：证据汇总，不新增语言规范，也不替代已有设计文档。本文件的主结论只统计代理
依据证据自动收敛的方案；用户明确选择、确认或改向的内容只作为排除记录保留。

## 统计口径

本文的重点是“代理自动选择的方案”，不是用户手动选择的方案。统计按决策族计数，
同一决策族中的实现细节只计一次。

- **严格自动**：代理根据现有源码边界、标准约束、工具链结果和测试证据自行收敛；
  会话中没有用户对该具体细节作方向性裁定。用户只说 `go`、`go on` 或继续推进，
  不视为一次手动选择。
- **推荐后确认**：代理先给出推荐，用户随后用 `ok`、`go` 或“开始实施”确认；这
  是最终采用的方案，但不计入严格自动。
- **手动选择/改向**：用户明确说 `pick A/B`、直接裁定方向，或推翻旧路线；不计入
  自动选择。
- **未决**：只有讨论或计划，没有足够的当前实现/测试证据；不把它写成已选方案。

证据优先级为：实现和测试 > 已完成计划/规范 > 讨论记录。设计文档能证明方案内容
和实施边界，但不能单独证明“是谁选择的”；因此本文对自动性的判断采用保守口径。

## 统计结果

| 分类 | 决策族数量 | 统计处理 |
| --- | ---: | --- |
| 严格自动 | 7 | 本文主统计对象 |
| 推荐后确认/用户影响 | 10 | 记录最终采用，但不冒充自动选择 |
| 明确手动 A/B 或改向 | 3 | 排除出自动统计 |
| 未决或证据不足 | 4 | 不计入已选方案 |

## 本轮复验

2026-08-04 对当前 G6.2 HTTP payload/request-body 实现重新执行了验证：

- `cd src && zig test build/codegen_component_wasi_http.zig`：`191/191` 通过。
- `cd src && zig build -Doptimize=ReleaseSmall`：通过。
- HTTP request-body lowering、producer lowering，以及已登记的
  `InternalError`/`DNS-error` payload-error lowering 和 ABI gate：通过。
- payload-error cancellation interaction 的已登记 HTTP pending slice 已闭合：
  `examples/p3-runtime/test_do_http_payload_cancellation.sh` 通过编译、WIT
  assembly、Core 导入检查和 Rust/Wasmtime cleanup gate；运行时观察一次 request
  consumption、一次 pending future drop、零 response create/drop 与空
  `ResourceTable`。更广的 payload/error 形状和 terminal/double/implicit
  cancellation 仍不计入已完成 gate。
- `./src/build/test/run_tests.sh`：`pass=1068 fail=0 skip=3`。
- `RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh`：`pass=1070 fail=0
  skip=3`，wasm smoke `pass=6 fail=0`；`cd src && zig test main.zig`：`232/232`
  通过；ReleaseSmall smoke 通过。
- `Status::Returned` 的 immediate completion 分支和 request-body 模板传播属于现有
  payload-error/HTTP lowering 决策族的实现细节，不新增公开语言方案，也不增加严格自动
  决策族数量；pending 路径仍保留 `waitable-join`。

## 严格自动选择

这些是代理在没有用户对具体细节作方向性选择时，根据工程约束自行收敛的方案。

| 项目 | 自动采用的方案 | 其他方案弃权理由 | 当前证据 |
| --- | --- | --- | --- |
| P3/WASI 证据分层 | Core GC、generic Component async、P3 host binding、完整 WASI 分开验收；探针不能越级宣称完整支持 | 用 feature flag、CLI smoke 或手写常用接口白名单宣称完成，缺少 pinned WIT、canonical ABI、host-driven runner 和逐接口矩阵 | `doc/host_abi_blockers.md:3-31` |
| Async 前端守卫 | 保留 `FuncSig.is_async`；resumable lowering 未完成时 `do build` 明确报 `AsyncLoweringUnavailable`；非法嵌套 Future 报 `InvalidAsyncReturn` | 静默把 async 当同步 WAT，或并行保留两套 Future ABI，会生成错误 artifact 或产生嵌套 ownership 歧义 | `/home/_/.codex/memories/MEMORY.md:89,101-102`；`docs/superpowers/plans/2026-07-31-component-async-function-plan.md` |
| Custom host import 验证 | CLI 无法注入 custom host import 时，使用 C embed runner 作为 authoritative runtime gate | 把 unresolved import 的 CLI 失败当作运行时语义失败，或只做静态 WAT 验证，无法证明 host-driven execution | `/home/_/.codex/memories/MEMORY.md:91`；`doc/host_abi_blockers.md:817-839` |
| Generic host-export 细节 | manifest 保存 source/export 名、参数/返回 ABI 和稳定 mangling；公开 callback 参数及字段未绑定的 unmanaged struct 早拒绝 | 公开函数值/closure、raw ABI，或静默接受不完整 struct，会把生命周期和字段替换风险推到 ABI 边界 | `/home/_/.codex/memories/MEMORY.md:92-93`；`doc/host_abi_blockers.md:59-106` |
| G6.2 扩展方式 | 只扩展 registry/descriptor 明确登记、且能由 pinned WIT + Core WAT + Component + runtime 证明的 bounded slice | 因工具能解析某个形状就泛化任意 async、producer、borrow/list/variant payload，缺少 layout、cleanup 和 runtime 证据 | `doc/design/2026-08-03-g6-2-general-resource-ownership.md:163-188` |
| Payload error ABI 验证顺序 | 先跑 hand-authored service-world probe，再对比编译器生成 WAT；未知 payload tag 显式 trap；禁止 `Some` 静默变 `None` | 仅凭八 word 签名直接改 emitter，或把 payload 丢失当兼容 fallback，会隐藏业务错误数据 | `docs/superpowers/specs/2026-08-04-g6-2-payload-error-abi-design.md:32-81,107-130` |
| G6.2 service-world payload gate | 先跑 hand-authored service-world ABI probe；`InternalError(Some("x"))` 绿后才进入 DNS/emitter；pending/ready 分开验证，ready 的 `Status::Returned` 不当作 handle，未知 payload tag 显式 trap，禁止 `Some` 静默变 `None` | 仅凭八 word 签名直接改 emitter，或把 payload 丢失当兼容 fallback，会隐藏业务错误数据；未先完成最小 payload gate 就扩展 DNS 会把 ABI 假设传入编译器 | `docs/superpowers/plans/2026-08-04-g6-2-payload-error-service-world.md:5-20,28-34,117-140`；`docs/superpowers/specs/2026-08-04-g6-2-payload-error-abi-design.md:32-81`；`/home/_/.codex/sessions/2026/08/04/rollout-2026-08-04T10-16-00-019fca8e-7263-7322-b900-178ec0a66e4d.jsonl:57730` |

严格自动统计的共同特点是：它们收敛的是证据门、边界和失败行为，而不是替用户新增
公开语言特性。

## 推荐后确认或用户影响

下列方向最终被采用，但会话中存在用户明确确认、改向或裁定，因此不计入严格自动数
量。表中仍保留它们，避免把“最终采用”误读成“自动选择”。

| 项目 | 最终采用 | 不计入自动的原因 | 证据 |
| --- | --- | --- | --- |
| WasmGC/ARC | 当前目标后端转向 WasmGC；ARC 保留为未来备选 | 用户明确裁定当前全量对接 GC、ARC 后置 | `/home/_/.codex/sessions/2026/07/27/rollout-2026-07-27T23-46-53-019fa441-f2e4-7d21-b589-dbee17658511.jsonl:5863-5864`；`doc/memory.md:7-29` |
| async 公共方向 | 采用 `async/await/Future/Stream`，清理旧 `do/channel/worker` 公共模型 | 用户明确要求恢复 async 方向并继续清理旧契约 | `/home/_/.codex/sessions/2026/07/28/rollout-2026-07-28T18-58-42-019fa860-778e-71f0-a042-d774e9917e01.jsonl:1251-1252,1553-1554` |
| `own<T>` / `borrow<T>` | 只保留内部 WIT/manifest/ABI 语义，不公开为普通 Do 类型 | 用户在评估后明确同意继续推进这一边界 | `docs/superpowers/specs/2026-07-30-wit-resource-ownership-design.md:31-65,96-101` |
| `Result<T,E>` | distinct arm 的普通 Do/API 使用 `T \| E`；`Result` 只保留给同型或私有 WIT/ABI 兼容 probe | 用户确认回到 Do union 用法；同型 result 仍需内部 tag | `docs/superpowers/specs/2026-07-29-result-core-design.md:3-8,45-80` |
| 取消语义 | 对齐 pinned Component/WASI 取消语义；已发出的 SQL、网络或文件副作用不回滚 | 用户明确裁定与 WASI 对齐 | `docs/superpowers/specs/2026-07-30-component-cancellation-lowering-design.md:19-46` |
| Do/WIT 大小写 | Do 核心保留 `Future/Stream/Tuple` 等拼写；WIT 保留规范小写 token；`Result` 不是 distinct arm 的默认源级写法 | 用户明确参与大小写取舍并随后裁定 distinct result 回到 Do union | `docs/superpowers/specs/2026-07-29-result-core-design.md:3-8,45-80` |
| UI host 边界 | UI 使用 generic host-export/manifest/ABI，不增加 `ui_bind_*` 等 compiler 特例 | 用户明确反对 UI 专用 compiler 识别 | `/home/_/.codex/memories/MEMORY.md:78-82`；`docs/superpowers/plans/2026-07-27-host-export-manifest.md:5-17` |
| Rust/Zig 分工 | Zig 维护 Do 编译器和构建入口；Rust 只用于 Wasmtime/Component host runner 验证 | 用户明确确认已有 Rust 环境并继续推进 adapter | `docs/superpowers/plans/2026-07-30-wit-resource-ownership.md:5-18` |
| pinned 工具链命名 | 暂用 `wasm-tools 1.254.0` 的 legacy async target `wasmtime-p3-legacy`，标准 `wasmtime-p3` 暂不启用 | 用户接受 pinned 路径；标准命名和完整成员证据尚未齐 | `/home/_/.codex/memories/MEMORY.md:86-87` |
| Wasmtime 驱动边界 | guest scheduler 管理逻辑任务；host 只驱动单个 Store/component future；取消后等唯一终态再 cleanup | 用户用 `ok` 确认了该整体修复方向，因此不计入严格自动；每个 do task 建一个 Wasmtime future 会触碰 single-Store/reentrancy，取消即释放 host frame/resource 可能造成悬空状态 | `/home/_/.codex/memories/MEMORY.md:88-99`；`doc/design/2026-08-03-g6-2-general-resource-ownership.md:148-161`；`/home/_/.codex/sessions/2026/07/27/rollout-2026-07-27T23-46-53-019fa441-f2e4-7d21-b589-dbee17658511.jsonl:5960,5966` |

### 推荐后确认方案的弃权理由

这两条弃权理由仍保留，供回溯方案取舍，但不计入严格自动决策族。

| 被放弃方案 | 弃权理由 | 当前处理 |
| --- | --- | --- |
| 每个 do task 对应一个 Wasmtime future | single-Store/reentrancy 边界不允许把每个逻辑任务直接变成独立 Store future | 单 future drive loop，逻辑任务排队 |
| Scope cancel 立即释放 host-held frame/resource | host 可能仍持有 frame/resource；立即 drop 会造成悬空或 double cleanup | 先等待唯一终态，再 drop/defer/invalidate |

## 明确手动 A/B 或改向

这些项目不是自动选择，应从“自动方案”统计中排除。

| 项目 | 用户选择/改向 | 统计处理 | 结果证据 |
| --- | --- | --- | --- |
| G6.1 preopens | 选择方案 A | 排除 | `doc/pending_blocked.md:35` |
| G6.3 sockets | 选择方案 B | 排除 | `docs/superpowers/specs/2026-07-13-g6-3-sockets-scheme-b-design.md:7-27` |
| WasmGC/i31 候选路线 | 对话中有明确候选方向，但没有独立的仓库决策/实现证据 | 排除；`i31` 仍无源语义落地证据，不能反推为自动选择或已完成方案 | `docs/superpowers/plans/2026-07-30-wit-resource-ownership.md:13`；`docs/superpowers/specs/2026-07-30-wit-resource-ownership-design.md:96-101` |

## 严格自动方案的替代路线与弃权理由

下表只回答严格自动决策对应的“其他方案为什么弃权”。“弃权”表示代理没有把它作为
当前路线，未必表示该方案在所有未来阶段都不可行。用户明确影响过的替代路线不放在本
表中，见前面的“推荐后确认或用户影响”和“明确手动 A/B 或改向”。

| 被放弃方案 | 弃权理由 | 当前处理 |
| --- | --- | --- |
| 用 feature flag、CLI smoke 或手写常用接口白名单宣称 P3/完整 WASI | 这些检查不能证明 pinned WIT、canonical ABI、host-driven execution、ownership 和 cancellation 矩阵 | 保持分层 completion gate |
| Core GC 或 generic async probe 宣称 P3/完整 WASI | probe 只证明局部机制，缺少 pinned WIT、canonical ABI、host runner、ownership/cancel 矩阵 | 维持分层 gate |
| 让 Wasmtime CLI 直接注入 custom P3 host import | 当前 CLI 不能注入 custom import；unresolved import 是工具能力边界，不是语言语义结果 | 使用 C/Rust embed runner |
| 因工具能解析某个形状就泛化任意 async、producer、borrow/list/variant payload | 解析成功不等于 layout、cleanup、runtime 和 cancellation 证据完整 | 只推进 registry/descriptor 已登记的 bounded slice |
| 直接按八 word 签名扩展 payload emitter | 参数个数不等于可工作的 lift；当前候选可能 trap 或改变 payload | 先做独立 ABI probe |
| `Some` payload 失败时静默降为 `None` | 会不可见地丢失错误数据，且让错误路径“看似成功” | 未登记/未证明的 tag 显式 trap |

## 未决，不计入统计

1. `own<T>` / `borrow<T>` 是否未来成为公开语法：需要新的生命周期规则和 pinned runtime gate。
2. Rust 编译器重写或自举：没有批准的目标、阶段、性能基线或回滚方案。
3. WasmGC 后端迁移是否完成：目标方向已确认，但全量 lowering 和回归证据尚未闭合。
4. HTTP payload error 的广义形状、注册形状之外的 ready runtime gate，以及
   immediate/terminal/double/implicit cancellation：已登记的 `InternalError`/
   `DNS-error` pending/ready slice 和显式 HTTP payload cancellation slice 已通过，
   更广边界仍未闭合。

## 结论

这几天自动收敛的主要是“怎么证明、在哪里拒绝、何时清理、如何避免静默丢数据”这类
工程方案；公开语言方向、后端路线、取消语义和 A/B 路线则由用户明确参与，已经从自动
统计中剥离。当前可确认的严格自动决策族为 **7 组**，不应扩大解释为用户没有参与的
语言设计裁定。
