# 非 G6 可推进 Todo（约 1 天量）

更新时间: 2026-07-12  
基线: 回归 `pass=913 fail=0 skip=3`; unit `119/119`  
约束: **不处理 G6.1–G6.3** (preopens API / read-directory async / sockets variant)  
权威入口: `doc/start_here.md` · 总规划: `doc/master_plan.md`

## 0. 范围

| 做 | 不做 |
| --- | --- |
| 发布维护、文档漂移、可独立验证的小增强 | G6 决策项与依赖 G6 的 host smoke |
| 不碰 skip `16` / `96` / `118` 的「收回」(依赖 WASI/recv) | 完整 ownership IR / direct wasm emitter / 合并双 runner |
| 单次只推进一个可验证小闭环 | 大规模重写 parser/sema/codegen |

验收默认命令:

```bash
cd src && zig test main.zig
./src/build/test/run_tests.sh
# 发布前再加: ./src/build/test/run_release_smoke.sh
```

---

## 1. 一天节奏（建议 6–8h）

按顺序吃；任一项做完就停在绿基线，不必硬塞满。

| 时段 | ID | 任务 | 预估 | 验收 |
| --- | --- | --- | --- | --- |
| 开场 30–45m | **D0** | 发布门禁复跑 + 基线对齐 | 0.5h | unit 117 全绿；`run_tests` 仍 `pass=911 fail=0 skip=3` 或更新文档数字；可选 `run_release_smoke` |
| 上午 1 | **D1** | 文档漂移清理（I2 后置已落地） | 0.5–1h | README「下一阶段 §8」去掉已完成的 I2 后置句；`start_here` / `master_plan` / `roadmap_status` 无矛盾表述 |
| 上午 2 | **D2** | 诊断与文档一致性扫一遍（非 G6） | 1h | `UnsupportedLowering` / Tuple 边界 / skip 列表与 fixture 一致；无「仍后置 path chain」类过期句 |
| 下午 1 | **D3** | 选 **一条** 产品小增强落地（见 §2 菜单，默认推荐 A） | 2–3h | 新/改 fixture + 绿回归 + 必要 `spec_rules`/`syntax` 一句 |
| 下午 2 | **D4** | 架构小拆（可选，与 D3 二选一或缩短） | 1.5–2h | 只抽纯函数/写出切片，行为不变；unit + 回归绿 |
| 收口 30m | **D5** | CHANGELOG + 基线回写 +（若要求）commit | 0.5h | `CHANGELOG.md` 有条目；`start_here` 基线正确 |

**一天结束定义**: D0 绿 + (D1 或 D2) 完成 + (D3 或 D4) 至少一个闭环；不强制 commit。

---

## 2. 产品小增强菜单（D3 选 1）

按「价值 / 风险 / 是否独立于 G6」排序。推荐从上往下选。

### A. Tuple 非 packable 叶子：更清晰诊断（推荐，低风险）

- **现状**: 裸 struct 等叶子 `[Tuple]` storage → 泛化 `UnsupportedLowering`
- **做**: 专用 hint（点名「非 packable 叶子 / 建议扁平字段」），必要时 `compile_err` 正例
- **不做**: 真降低 bare struct pack（那是更大项，见 backlog B）
- **触点**: `src/build/diag.zig`、codegen 报错点、`compile_err/*`、`doc/spec_rules.md` 一句
- **验收**: 新 expect 子串稳定；全量回归绿

### B. Tuple bare-struct 叶子 storage 真 lowering（中风险，可占大半天）

- **现状**: scheme A 仅 packable 叶子（标量 + managed handle）
- **做**: 评估是否把「无 managed 字段的小 struct」当固定宽度 pack 叶子；或明确永远后置
- **门槛**: 先写 1 页决策（宽度/对齐/ARC 子字段）再动 codegen；无决策则退回 A
- **触点**: `type_name.zig`、`codegen_payload_wat.zig`、`codegen.zig`、storage-pack layout
- **验收**: `compile_ok` + `compiled_ok` 各至少 1；managed 字段 struct 仍拒绝或单独路径

### C. JSON 边界收窄一小步（中风险）

- **现状**: struct 字段 stringify/from_json 已有；error/enum/union/复杂 storage 后置
- **做**: 只挑 **一种** 已接近的类型（例如「仅 nullable 标量字段」或「仅 `[u8]` 字段」若尚未稳）补正例 + 明确仍拒绝列表
- **不做**: 通用 union/error 自动序列化
- **触点**: `lib/` JSON 相关、`ok`/`err` fixture、`doc` 一句
- **验收**: 行为有 fixture 锁；回归绿

### D. Ownership 保守增强一小步（中风险）

- **现状**: `OwnershipFacts` 增量路径；完整 IR 不启动
- **做**: 从 `doc/memory.md` 已写明的「证据不足则 reject」里，挑 **一个** 可证明的 call/return 场景减少多余 `inc`（必须有 before/after WAT 或 compiled 行为差）
- **不做**: loop 内激进 move、跨函数唯一性、escape analysis
- **触点**: `ownership_facts.zig`、`codegen.zig`、`compiled_ok` ARC 相关
- **验收**: 无语义回退；至少 1 条 fixture 锁住新允许路径

### E. LSP / fmt 小增强（低–中风险）

- **LSP 可选**: Tuple 类型 hover 更可读；或 definition 对 `@get` 路径首段更稳（**不做** rename/references）
- **fmt 可选**: 单一已知丑格式边角（尾逗号 / 多返回换行）规范化 + `fmt` fixture
- **验收**: `src` 下相关 unit + harness `lsp`/`fmt` 绿

### F. 泛型递归「左侧目标类型反推」（高风险，不建议塞进同一天 D3）

- **现状**: 仅靠左侧类型反推的泛型递归 → `NoMatchingCall`
- **建议**: 单独开半天以上；今天最多做 **复现 fixture + 根因笔记**，不落实现

---

## 3. 架构 / 质量菜单（D4 或第二天）

| ID | 任务 | 预估 | 备注 |
| --- | --- | --- | --- |
| **R1** | codegen 垂直再拆：WASI/component **已存在** emit 路径抽纯写出 helper | 2–3h | 只搬代码，不扩 G6 能力；先 parse/validate 边界再搬 |
| **R2** | `codegen.zig` 再抽「path get 链式」或「storage pack clone」为 payload/storage 旁路 | 1.5–2h | 行为零 diff；优先减小热点函数长度 |
| **R3** | `sema` 错误构造再收敛到 `sema_error`（若仍有散落） | 1–2h | 不改诊断语义 |
| **R4** | unit 补强：`type_name` / pack width / path chain 边界表驱动 | 1h | 目标 unit 不掉红 |
| **R5** | fixture 编号/README 索引与真实目录对齐审计 | 0.5–1h | `compile_ok`≈272 / `compiled_ok` 77 / `compile_err` 39 |

---

## 4. 发布维护清单（随时可插入）

- [x] **M1** `cd src && zig test main.zig`
- [x] **M2** `./src/build/test/run_tests.sh` → 记录 pass/fail/skip
- [x] **M3** `./src/build/test/run_release_smoke.sh` → passed
- [x] **M4** 可选 `RUN_WASM=1` → **deferred** 耗时长; 基线 `pass=833` 未重跑, 不阻塞 (恢复: 发布前显式跑)
- [x] **M5** 文档入口交叉链：`README` ↔ `start_here` ↔ `master_plan` ↔ `roadmap_status` ↔ `CHANGELOG`
- [x] **M6** 删除或改写过期表述（尤其 I2 后置、错误基线数字）

---

## 5. 明确今天不做（避免走偏）

| 项 | 原因 |
| --- | --- |
| G6.1 / G6.2 / G6.3 及 preopens/sockets/read-dir 实现 | 用户暂缓 |
| 收回 skip `16_loop_recv_value` / `96_file_lib_resource_shape` / `118_wasi_p3_std_wrappers` | 依赖 WASI/recv/host |
| 完整 ownership IR / region / escape analysis | 启动条件未满足（见 `doc/memory.md`） |
| direct wasm binary emitter 替换 WAT 主路径 | 非目标 |
| `backend_ir` 升主 emit | 需单独立项 |
| 合并静态 / compiled 双 runner | 刻意未做 |
| 去掉内部 `@` 前缀；重开 get/pkg/push | 产品禁区 |
| LSP rename / 完整 references | v1 后 |

---

## 6. 可勾选总表（复制用）

### 今天必选骨架

- [x] D0 门禁复跑
- [x] D1 文档漂移（I2 已落地）
- [x] D2 诊断/文档一致性
- [x] D3 产品小增强（圈选: **A** / B / C / D / E ）→ `UnsupportedTupleStorageLeaf` + `compile_err/339` (push `14a55d2`)
- [x] D4 架构小拆 → **R4** packable-leaf unit 表 (`type_name.zig`, push `852bd37`); **R5** 计数审计 compile_ok=272/compiled_ok=77/compile_err=39; R1/R2 见 deferred
- [x] D5 收口 CHANGELOG + 基线 (随各 push)

### 近期待选（第二天起，仍非 G6）

- [x] B Tuple bare-struct pack → **deferred** 正式后置 (`UnsupportedTupleStorageLeaf` + §9); 不实现真 pack
- [x] C JSON 单一类型扩展 → `u8` 字段 stringify/from_json (`ok/190`, push `a3f79b2`)
- [x] pure-scalar `field_set` return → **fixed** collect 跳过已有 struct rebinding (`ok/191`)
- [x] D Ownership 单一场景少 inc → **deferred** 无安全可证明单点 (loop/defer/IR 门槛见 memory 03.8); 恢复: 授权 ownership 小项
- [x] E LSP/fmt 边角 → LSP 类型名 hover (`src/lsp/hover.zig`, push `a3f79b2`); fmt 无新增边角
- [x] R1–R2 codegen 再拆 → **R1 deferred** §9; **R2 deferred** 零行为大搬迁非日路径; 恢复: 单独授权垂直切片
- [x] F 泛型递归左侧反推 → **deferred** 单独立项 (§9); 边界仍 `NoMatchingCall`
- [x] 诊断码表抽样 → 已记录: `Unsupported*` 7 条 compile_err (含 339); `NoMatchingCall` 13 条 overload/能力边界混用处 (JSON union/enum 等仍 NoMatchingCall); **不**批量改码

---

## 7. 推荐默认路径（不想选的时候）

若只说「按 todo 推进一天」且不指定菜单：

1. **D0** 门禁  
2. **D1 + D2** 文档与表述收口（含 README §8 过期句）  
3. **D3 = A** Tuple 非 packable 诊断清晰化 + fixture  
4. 有余力再 **R4** 或 **R2** 小拆  
5. **D5** 收口  

预计产出: 文档干净 + 1 个用户可见诊断改进 + 绿基线；风险可控，不碰 G6。

---

## 8. 推进协议（与仓库一致）

1. 一次一个可验证目标；失败独立回退。  
2. 语法/语义变 → 同步 `spec_rules` / 相关 `syntax/*` / fixture。  
3. 工具行为变 → 同步 `README` / `src/build/test/README.md`。  
4. 完成后更新本文件勾选状态，并回写 `doc/start_here.md` 基线数字（若变化）。  
5. **每完成一步可验证闭环 → commit + push `origin/main`** (正常推送, 不 force-push)。  
6. 无法完成的项必须在本文件标 **blocked/deferred** 并写恢复条件; G6.1–G6.3 永不静默删除。  
7. 阻断项同步到 `doc/start_here.md` 或 `doc/roadmap_status.md`。

## 9. 阻断与后置登记（非静默缺口）

| ID | 状态 | 原因 | 恢复条件 |
| --- | --- | --- | --- |
| G6.1 | **blocked** | preopens `list<tuple<descriptor,string>>` 公开 API 未确认 | 用户确认 API |
| G6.2 | **blocked** | `read-directory` 依赖 stream/future; 无 async runtime | async/Future/Task 立项 |
| G6.3 | **blocked** | sockets resource + variant 映射未定 | 用户确认 wrapper/address variant |
| skip 16/96/118 | **deferred** | 依赖 recv/WASI/host; 非 G6 日路径不收回 | G6 + host smoke 后单独开项 |
| B bare-struct pack | **deferred** | 需宽度/对齐/ARC 子字段产品决策; 当前正式后置为 `UnsupportedTupleStorageLeaf` | 用户授权 + 决策页后实现 |
| F 左侧泛型递归 | **deferred** | 高风险 sema; 日路径只保留边界说明 | 单独立项 (半天+) |
| 完整 ownership IR | **blocked** | `doc/memory.md` 启动条件未满足 | 见 memory 03.8.4 |
| R1 大拆 WASI emit | **deferred** | 多小时零行为搬迁; 日路径优先小 R 项 | 单独授权垂直切片 |
| R2 path/pack 再抽 | **deferred** | 零行为搬迁; 已有 payload/storage 旁路够用 | 单独授权垂直切片 |
| D ownership 少 inc | **deferred** | 无证据充分的单场景; 完整 IR 门槛未满足 | 用户授权 + 可证明 call/return 场景 |
| M4 RUN_WASM 全量 | **deferred** | 耗时长; 不阻塞默认回归 | 发布前显式 `RUN_WASM=1` |
| pure-scalar struct `field_set` return | **fixed** | field 反射循环误把 `out = @field_set(...)` 收集为 scoped shadow (`__field_*_out`); 写 `$out.n` 读 shadow | 已修: collect 跳过已有 `struct_locals`; fixture `ok/191` |
