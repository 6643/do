# 待处理与阻断清单

更新时间: 2026-07-13  
基线: 默认回归以 `./src/build/test/run_tests.sh` 最新结果为准  
关系: 总规划 `doc/master_plan.md`; 接手 `doc/start_here.md`; 执行状态 `doc/roadmap_status.md`  
约定: **只记未关闭项**; 完成后从本文件删除或移入「已关闭摘要」, 并同步入口文档与 `CHANGELOG.md`。

## 图例

| 标记 | 含义 |
| --- | --- |
| **blocked** | 缺产品/runtime 决策, 禁止绕过扩实现 |
| **pending** | 能力缺口已明确, 可单独授权后做 |
| **deferred** | v1 非目标或日路径不自动开, 需明确立项 |
| **skip** | 回归故意跳过, 与后置能力绑定 |

---

## 1. 阻断 (blocked) — G6 WASI / Component

| ID | 问题 | 证据 / 停止点 | 恢复条件 |
| --- | --- | --- | --- |
| **G6.2** | `descriptor.read-directory` | 依赖 stream/future; **无** async/Future/Task runtime | 未来 async runtime 设计立项 |
| **06.2** | 历史总项 | 已拆到 G2–G6; 剩余由 **G6.2** 承接 | 同上 |

**规则**: 无新决策时 **不** 绕过 G6.2 扩 WASI async/stream codegen。

**G6.1 已关闭 (方案 A)**: `preopens.get-directories` → do `[Tuple<i32,text>]` host / 公开 `preopen_directories() -> [Tuple<Dir, text>]`; list-of-tuple resource lowering + `lib/dir.do`; 见 `compile_ok/274`–`275`。

**G6.3 已关闭 (方案 B)**: sockets `tcp/udp-socket.create|bind|drop` 可 lower; 地址为 dual concrete + `IpSocketAddress = V4|V6` payload enum; resource shell + 粗粒度 `TcpError`/`UdpError`; stdlib `lib/tcp.do` / `lib/udp.do` / `lib/net.do`; 见 `compile_ok/291`–`294` 与 `docs/superpowers/specs/2026-07-13-g6-3-sockets-scheme-b-design.md`。真 host smoke 仍属 **D2**。

---

## 2. 待处理 (pending) — 语言 / codegen 已知缺口

### P2. 泛型递归: 仅靠左侧目标类型反推

| 项 | 内容 |
| --- | --- |
| 状态 | **pending** (产品原则: 默认 **不** 放开) |
| 现象 | `out i32 = generic_countdown(2, 9)` → `NoMatchingCall` |
| 锁点 | `err/329_generic_recursive_target_type_only_uninferred` |
| 已支持对照 | 参数侧已定型: `seed i32 = 9; generic_countdown(2, seed)` (`ok/184`) |
| 原则 | 调用点参与决议的类型须在 **实参侧已知**; 泛型位先绑有类型局部再传入, 不靠左侧静默反推 (避免 monomorphize 分支不明) |
| 恢复条件 | 若改原则须单独规格 + 实现; 否则保持失败, 可仅改善诊断文案 |

### P3. 回归 skip (与 host / WASI 后置绑定)

| Skip fixture | 状态 | 说明 |
| --- | --- | --- |
| `16_loop_recv_value` | **skip** | recv 相关后置 |
| `96_file_lib_resource_shape` | **skip** | file/resource shape; 真 host I/O 后置 |
| `118_wasi_p3_std_wrappers` | **skip** | WASI p3 std wrappers; 依赖 G6 / host |

恢复: G6 决策 + 真 host smoke 后再收回, 不在默认回归里强行变绿。

---

## 3. 延期 (deferred) — v1 非目标 / 需单独授权

| ID | 项 | 说明 |
| --- | --- | --- |
| D1 | 完整 ownership IR | 跨函数唯一性 / escape / region / 激进 loop move; 门槛见 `doc/memory.md` |
| D2 | 完整 WASI/Component 运行时 | 真 host file/dir/stream/socket/http; 不单靠 G6.1–G6.3 API 决策 (G6.3 已 close API 层) |
| D3 | JSON 自动序列化扩展 | error/enum/union/复杂 storage; 当前仅已验证 struct 字段子集 |
| D4 | LSP 增强 | rename / references / import-aware 跨模块 / 增量 index |
| D5 | fmt 增强 | 多文件批量、range/on-type、完整语法感知 |
| D6 | direct wasm binary emitter | 不替换 WAT 主路径; 仅并行评估 |
| D7 | codegen 垂直再拆 | 如 WASI emit 切片; 先 parse/validate 再搬; 需授权 |
| D8 | 包管理 get/pkg/push | 不重开 |
| D9 | `RUN_WASM=1` 全量扩展回归 | 耗时长; 发布前显式跑, 非默认日路径 |

详见 README「v1 非目标」与「下一阶段计划」。

---

## 4. 设计硬约束 (非待办, 实现必守)

| 约束 | 说明 |
| --- | --- |
| Tuple **永不拍平** | 嵌套 `Tuple` / struct 直接子槽保持嵌套类型与 `@get` 路径; 禁止与扁平 Tuple 等同或隐式 coerce |
| 泛型调用类型已知 | 函数要用的类型在实参侧已知; 不默认左侧反推 direct type param |
| G6 不绕过 | 无决策不扩 read-dir (async) codegen; sockets create/bind/drop 已按 G6.3 B 落地 |

权威条文: `doc/spec_rules.md` (Tuple 节等)。

---

## 5. 已关闭摘要 (勿当待办)

- pure-scalar struct 作为 Tuple storage 嵌套子槽 (`compile_ok/272`, `ok/192`; 局部名 `$pair.0.x`)
- managed/`text` 作为 Tuple **直接叶子** storage + path chain (`compile_ok/270`–`271`)
- **P1** 含 managed 字段的 struct 作 Tuple 直接子槽: 句柄叶子 + storage pack ARC (`compile_ok/273`, `ok/193`; 不拍平 `Cell` 字段)
- pure-scalar field-reflect `field_set` 误 shadow (`ok/191`)
- 阶段 A–F、H、I (I1+I2) 主线; G1–G5、G6.1、G6.4
- **G6.1** preopens 方案 A: host `[Tuple<i32,text>]` + `preopen_directories() -> [Tuple<Dir, text>]` (`compile_ok/274`–`275`)
- **G6.3** sockets 方案 B: create/bind/drop + dual address + payload enum + stdlib wrappers (`compile_ok/291`–`294`)

---

## 6. 推进顺序建议

1. 发布候选维护 (回归红灯 / 文档漂移)  
2. **等 G6.2 决策** (blocked: read-directory / async)  
3. 可选授权: deferred 项 (ownership / JSON / LSP / codegen 再拆 / D2 真 host) — 默认不自动开做  
4. **P2** 默认不改; 除非产品明确要左侧反推  

用户说 `go` / `next` 时以 `doc/start_here.md` §6 为准, 细节以本文件为准。
