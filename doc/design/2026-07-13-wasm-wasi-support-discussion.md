# 讨论纪要：Wasm / WASI 一等支持、引用与边界模型

**状态:** 讨论存档 / **非实现授权** / **议题搁置**  
**日期:** 2026-07-13  
**关系:**

- 已定策略（未实现）: [wasm_ref_host_syntax.md](wasm_ref_host_syntax.md)（D10）
- WASI lowering: [../wit/wasi_p3_lowering.md](../wit/wasi_p3_lowering.md)
- 延期: [../pending_blocked.md](../pending_blocked.md)（G6.2 async、D2 真 host、D10 host_ref）
- 入口: [../start_here.md](../start_here.md)

本文汇总会话中的设计讨论，便于以后续议。**当前不据此改代码、不开 G6.2 / `@host_ref` 实现。**

---

## 1. 产品前提

- 语言最终目标是 **编译到 Wasm**（build wasm 为唯一主产物方向）。
- 语言硬约束：**值语义**、**无指针/引用语法**、**显式 close**（drop 值 ≠ 关资源）、**exclusive** `T | E`。
- 主轨倾向：**WASI 0.3 + Component / cm32p2 客户**，不是 C 指针 ABI，也不是 JS 超集。

---

## 2. 分层：用户值 vs 边界凭证

```text
L0  公开 do：File / text / TcpSocket / 错误联合 — 只有值
L1  私有边界：@host / @wasi_resource
L2  Codegen：handle id、ptr+len、result area、登记 lowering
```

**原则：** 新能力先定 L0/L1 形状，再开 L2；禁止把 WIT/Wasm 关键字直接暴露给用户。

---

## 3. Wasm「引用」必须拆开（勿混为一谈）

| 概念 | 层 | 是什么 | do 侧 |
| --- | --- | --- | --- |
| 线性内存 `i32` 偏移 | Core | 像指针的 **数** | **永不** 做 do 类型；`text`/`[u8]` 等 lowering |
| WASI resource handle | WASI/CM | 表下标 / **id** | `@wasi_resource` + 私有 `.id`（已有） |
| WIT `borrow` / `own` | WIT | 调用期所有权约定 | 无 `&T`；仍传 id；borrow 仅 ABI |
| `externref` / `anyref` | Core | 宿主对象引用（常挂 JS 堆） | **非 WASI 类型**；策略见 D10 |
| `funcref` | Core | 函数引用 | 非一等类型；export / 回调 id |

**结论：WASI 并不「自带」externref/anyref/funcref。**  
那些是 **Core Wasm** 引用类型；WASI 用 **resource/handle**。

---

## 4. 已记录的语法策略（D10，未实现）

| 概念 | 策略 |
| --- | --- |
| externref | 将来可选 `@host_ref("…")` 值壳，对齐 `@wasi_resource` |
| anyref | **不做** 公开语法 |
| funcref | **不做** 一等类型；export / 回调 id；必要时再 `@host_func` |
| i32 内存指针 | **永远不是** do 类型；只活在 `@host` / wasi lowering |

权威全文: [wasm_ref_host_syntax.md](wasm_ref_host_syntax.md)。

---

## 5. 不做 `@host_ref` 时怎么搞

**可以不做。** 不是不能上 Wasm，而是：

1. **主路径：纯 WASI/Component 客户** — 文件/socket 用 handle id；字符串用内存编组。不需要 externref。
2. **浏览器/JS：Host 封装 + do 只调 base types**  
   - Host（JS）握 DOM/真对象、自己的 `id → 对象` 表  
   - do 只传标量、`text`/`[u8]`、应用层整数 id  
   - 对象与 GC 留在 host
3. **可选：** glue 层手写 ref；不进 `.do` 类型系统。

**一句话：** Host 包一层复杂世界；do **call base types（含句柄数字）**。

---

## 6. 外部调用 ABI（直觉校正）

| 误解 | 更准确 |
| --- | --- |
| 每次先传「函数编号」 | 链接期绑定的 **import 名** + `call`（非参数里的函数号） |
| 参数只有「地址或立即数」 | **标量 + memory ptr(+len) + resource 句柄 id** |
| 复杂结果 = host 返回指针 | 常见是 **guest 提供 result area，host 写入** |
| 新资源 = 对象指针 | 新 **handle id**，再封进 `File{id}` 等 |

---

## 7. externref 与 GC

- **`externref` 与 GC 有关**：对象在 **宿主堆**；Wasm 持有 ref 常作为 **宿主 GC 的根**。
- **`funcref`**：与对象 GC 关系弱。
- **WASI handle id**：**不是** guest/宿主 GC 对象；靠 **显式 drop/close**。
- **do ARC**：只管 guest managed 值；**不管** JS 对象，也 **不** 自动 close 资源。

不做 `@host_ref` ⇒ do 不参与宿主 GC 根。

---

## 8. D2 是什么

- **D2**（`pending_blocked` deferred）：**完整 WASI/Component 运行时 + 真 host I/O smoke**。
- 与 **G6.x** 区别：G6 = API/类型/lowering 能否编译；D2 = 真宿主上能否真跑 I/O。
- G6.3 sockets API 已关；**真 bind 端口等 smoke 仍属 D2**。
- 勿与历史主线「阶段 D / D2.1」混淆。

---

## 9. 异步何时做

- **G6.2 blocked**：`descriptor.read-directory` 等依赖 stream/future。
- **无 async/Future/Task runtime 设计立项 ⇒ 不扩** stream codegen。
- 开始顺序建议：规格 → 最小 runtime → 再 lower 一个 API；禁止半套。
- 当前：异步 **搁置**，与本文议题一并先放。

---

## 10. 「更好的设计」讨论摘要（未拍板实现）

在 **不推翻值语义** 前提下，比「无限手写 known 表」更可取的方向包括：

| 方向 | 要点 |
| --- | --- |
| World / 映射 SSOT | Component-native：world 驱动 binding，模板 lowering |
| 可编组类型规则 | 类型系统一等：何物可过 host 边界 |
| 资源 kind | 比「带私有 id 的普通 struct」更硬的 resource 语义 |
| D2 闭环 | 「一等 Wasm」含真跑通，不只 compile 绿 |
| Async 分轨 | 第二程序形；勿污染同步主路径 |
| JS 分轨 | 默认 host 封装；`@host_ref` 仅可选 |
| Wasm GC 后端 | 理论贴值语义；**不宜** 现作唯一主后端 |

**不必为 Wasm 加 `*T`/`&T`。** 哲学可保留；升级点在 SSOT、模板、闭环。

---

## 11. 「根本问题是没有引用吗？」

**不完全是。**

- 主路径（WASI 客户）**不是**「缺引用就无法支持 Wasm」——句柄 id + 编组已可工作。
- 更准确的张力是：**语言只有值；边界上有凭证（id / 内存偏移 / 可选宿主 ref）与多套生命周期（ARC / resource / 宿主 GC）**。
- 仅当目标是 **JS 对象在 guest 里一等传递** 时，才突出「缺宿主 ref 壳」；解决可以是 `@host_ref` **或** host 封装，**不是** C 式指针。

---

## 12. 议题状态与后续

| 项 | 状态 |
| --- | --- |
| 本讨论 | **搁置**；先进入其它议题 |
| D10 `@host_ref` | 策略已记，**不实现** |
| G6.2 async | **blocked**，等立项 |
| D2 真 host | deferred，需授权 |
| 推荐续议入口 | 本文 + `wasm_ref_host_syntax.md` + `pending_blocked` |

**恢复本议题时建议先读：** §3（拆引用）、§5（不做 host_ref）、§11（根本问题校正）。

---

## 13. 修订

| 日期 | 说明 |
| --- | --- |
| 2026-07-13 | 初版：会话讨论存档，议题搁置 |
