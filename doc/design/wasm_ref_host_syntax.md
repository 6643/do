# Wasm 引用类型与 do 语法策略（记录在案）

**状态:** 已决议方向 / **未实现** / **非当前迭代**  
**日期:** 2026-07-13  
**关系:** 值语义与无指针铁律见 `doc/memory.md`、`doc/spec_rules.md`；WASI resource 见 `doc/wit/wasi_p3_lowering.md`；延期项见 `doc/pending_blocked.md`（D10）。
**扩讨论存档（含 host 封装、GC、D2、async、「是否缺引用」）:** [2026-07-13-wasm-wasi-support-discussion.md](2026-07-13-wasm-wasi-support-discussion.md) — 该议题已搁置。

本文只固定 **语法与边界策略**，不授权实现。实现须单独立项（通常在有 JS/浏览器 host 产品需求时）。

---

## 1. 背景

Core Wasm 与宿主（尤其 JS）边界上常见：

| Wasm 概念 | 含义（概念） |
| --- | --- |
| `externref` | 任意宿主/JS 值引用（不透明） |
| `anyref` | 更泛的引用层级（含 externref 等） |
| `funcref` | 函数引用 |
| `i32` 作为 memory 指针 | 仅指向 **Wasm 线性内存** 偏移，不是 JS 对象 |

do 源码 **无指针、无引用语法**；WASI resource 已用 **`@wasi_resource` + 私有 `.id` 句柄值**（表下标/id，非内存指针）。  
二者都不是 guest 线性内存指针，但 **机制不同**，语法上 **不得合并成一种万能 Ref**。

---

## 2. 定案：语法策略

| 概念 | 语法策略 | v1 / 现状 |
| --- | --- | --- |
| **externref** | 做 **`@host_ref("…")` 值壳**，形态对齐 `@wasi_resource`（不透明值，可传参；不可算术、不可解引用、不可与 i32 互转伪造） | **未实现**；有 JS/host 对象需求时再立项 |
| **anyref** | **不做** 公开语法；不出现 `AnyRef` / `@any_ref` | 永久（公开层）；若 ABI 需要仅限编译器内部 IR |
| **funcref** | **不做** 一等源码类型；优先 **export 具名函数** / **回调 id 表**；仍不够时再考虑 `@host_func("…")` 壳 | 默认不做值类型 |
| **i32 指针** | **永远不是** do 类型；只活在 `@host` 的 **私有签名与 codegen lowering**（如 `text`/`[u8]` → ptr,len；result area 偏移） | 已是现行方向，保持 |

**源码禁止泄漏 Wasm 关键字：** 用户不写 `externref` / `anyref` / `funcref` / 内存指针类型。

---

## 3. 与现有壳的分工

| 边界 | do 壳 | 载体（概念） |
| --- | --- | --- |
| WASI / Component resource | `@wasi_resource("…", { .id i64 })`（已有） | 整数 handle / 表项 id |
| WIT `borrow` / `own` | **无** 公开引用类型；borrow 仅 **单次 host 调用** 的 ABI 模式 | 仍传同一 handle id |
| JS / 任意宿主对象 | 将来 `@host_ref("…")` | `externref` |
| 线性内存数据 | 公开用 `text` / `[u8]` / struct 等值类型 | lowering 为 i32 ptr(+len) |
| 可被宿主调用的 guest 函数 | 导出机制（非 funcref 源码类型） | 链接/export |

`@host_ref` **不得** 用来重做 `File`/`Dir`/`TcpSocket`；resource 继续走 `@wasi_resource`。

---

## 4. 概念语法（仅文档示意，非现行语法）

```do
// —— 未实现；勿写入 stdlib / 测试当作已支持 ——

JsObject = @host_ref("js/object")

.host_id = @host("env", "js_identity", (JsObject) -> JsObject)

// 公开仍是值传递；无 * / & 
identity(o JsObject) -> JsObject {
    return host_id(o)
}
```

`@host` 签名 **推荐写 do 类型名**（`JsObject`、`text`），**不** 写 `externref` 或裸 memory 指针类型。

---

## 5. 硬约束（实现时必守）

1. **值语义:** 壳是值；拷贝语义须在实现规格中写死（复制凭证 ≠ 深拷贝对象）。  
2. **无伪造:** 禁止 `@bitcast` / 与 i32 互转构造 host_ref 或指针。  
3. **无解引用:** 不能对壳做字段访问（除非将来显式 host API）；真逻辑在 host 侧。  
4. **登记式边界:** 仅登记过的 `@host` 可接受该壳；禁止「任意 externref 自动互通」。
5. **生命周期:** drop 壳值 **不** 隐式 dispose 宿主对象（与 resource「drop 值 ≠ close」一致）；若需要释放，走显式 API。  
6. **async/stream/future** 与本文无关；仍受 G6.2 等阻断，不靠 `@host_ref` 解决。

---

## 6. 明确不做（避免脑内方案膨胀）

- 公开 `*T` / `&T` / 内存指针类型  
- 用引用语法表达 WIT `borrow`  
- 统一 `Ref` + 运行时 tag 模拟 anyref  
- 普通 do 函数值与 funcref 隐式互通（无完整函数值/捕获模型前）  
- 析构自动 resource-drop / 自动释放 host 对象  

---

## 7. 建议落地顺序（将来，非现在）

1. 有明确 JS/浏览器（或其它 externref host）产品需求。  
2. 实现前补一页可测试规格：构造/拷贝/存储/与 `@host` 表。
3. 实现 `@host_ref` + 少量 fixture；stdlib 按需薄包装。  
4. 回调优先 export / id 表；最后才考虑 `@host_func`。  

**当前迭代:** 不实现；主线继续其它项（回归维护、G6.2 等待决策、已授权 deferred 等）。

---

## 8. 修订

| 日期 | 说明 |
| --- | --- |
| 2026-07-13 | 初版：记录 externref/anyref/funcref/i32 指针语法策略，明确未实现 |
