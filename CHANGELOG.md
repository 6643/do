# Changelog

- Continue gen split: `gen_union.zig` (layout types/helpers); extend `gen_wasi` (call-shape / lowerability) and `gen_util` (type separators)

- Split `gen.zig`: extract `gen_util.zig` (token helpers) and `gen_wasi.zig` (WASI tables/parse)

- Rename codegen modules to `gen_*` prefix: `gen.zig`, `gen_payload_wat.zig`, `gen_storage_wat.zig`

- Payload enum L1: `Message = Quit | Text([u8]) | Binary([u8])` declare/construct/`@is` narrow (tags by case name)
  - sema: `isPayloadEnumDeclStart` + branch validation; codegen: tag+max-payload layout, unit/payload ctors
  - fixtures: `compile_ok/289`–`290`, `compile_err/339`; docs: `syntax/enum.md`, `grammar.peg`

- WASI C+D: stream hosts use coarse `StreamError` Err arms; docs inventory aligns preopens/stream preferred do forms
  - `lib/io.stream.do`: `[u8] | StreamError`, `u64 | StreamError`, `StreamError | nil`
  - docs: `preopens` lowerable; preferred examples use DirError/FileError/StreamError and `[Tuple<Dir,text>]`


本文只记录**最近仍需可追溯**的已完成变更。实时停点见 `doc/start_here.md`; 总规划见 `doc/master_plan.md`。  
更早条目已从仓库移除, 需要时查 git 历史。

## 2026-07-12

- 文档: WASI host 签名优先 do 联合 `Ok | Err` / `T | nil`
  - 推荐: resource/record 名 + 排他联合；禁止多返回作为 WASI result 模型；无 `wasi_result`/`wasi_option`/`@wasi_tuple`
  - 过渡: 已知 target 仍接受源码 `result<>`；manifest 仍存 WIT
  - 更新: `spec_rules` §21.1/§23、`wasi_p3_lowering` Declarative host surface、`grammar.peg` `WasiHostResult`

- 声明式 WASI 宿主绑定（stdlib 对齐）
  - 新形式: `@wasi_func` / `@wasi_resource` / `@wasi_record`（`@wasi_enum` 语法预留；粗 `DirError`/`FileError` 仍手写）
  - 已移除裸 `@wasi(...)` 别名；codegen 对已知 target 把 do 侧糖（`i32`/`[u8]`）规范为 WIT 签名
  - stdlib: `lib/time.do`、`dir.do`、`file.do`、`random.do`、`io.stream.do` 迁移；host 行保持 import 前缀
  - fixtures: `compile_ok/276_wasi_func_do_sig_and_resource`；私有字段收集覆盖 wasi_resource 声明
  - 文档: `grammar.peg`、`spec_rules` §21.1、`wasi_p3_lowering` declarative surface

- WASI G6.1 方案 A: `filesystem/preopens/get-directories`
  - host: `() -> list<tuple<descriptor,text>>` → do `[Tuple<i32,text>]` (`$__wasi_list_preopen_to_storage`)
  - 公开: `preopen_directories() -> [Tuple<Dir, text>]` (`lib/dir.do`); 调用方 `close_dir` 各根
  - component plan / core import / WIT (`use types.{descriptor}`) 可 lower
  - fixtures: `compile_ok/274`–`275`; 更新 `124` companion expects
  - 文档: `pending_blocked` G6.1 关闭; `wasi_p3_lowering` / start_here 同步

- codegen: **P1** 含 managed 字段的 struct 作 Tuple storage 直接子槽 (永不拍平)
  - `items [Tuple<Cell, u8>]` 且 `Cell` 含 `text` → pack 为 **4B ARC 句柄叶子** + 标量槽; 类型仍是 `Cell`, 不展开字段
  - put/get/path owning load 与 storage pack clone/free 走 `is_storage_pack` managed offset 表
  - 顺带修: multi-leaf pack 共用 `__tuple_pack_spill_i32` 导致 `text+u8` / `Cell+u8` 叶子互相覆盖 → 按叶子索引用 `_1/_2/_3` spill
  - fixtures: `compile_ok/273`, `ok/193` (`compiled_must_pass`); 删除旧 `compile_err/339`
  - 文档: `pending_blocked` P1 关闭; README / start_here / master_plan 同步

- 文档: 新增 `doc/pending_blocked.md` — 阻断 (G6)、待处理 (P2 泛型左侧反推 / skip)、延期非目标与硬约束; `start_here` / `roadmap_status` / `master_plan` / README 指向该文件

- codegen: pure-scalar 具名 struct 作为 Tuple storage **嵌套子槽** (永不拍平)
  - `items [Tuple<Point, u8>]` / `@put` / `@get` / path `@get(items, i, 0)` → `Point`
  - 局部 `Tuple` 槽用位置名 `$pair.0.x` / `$pair.0.y` / `$pair.1` (不是假字段 `v0`)
  - fixtures: `compile_ok/272`, `ok/192` (`compiled_must_pass`)

- codegen: Tuple 局部/参数槽位命名 `vN` → 位置下标 `N` (`$pair.0` 而非 `$pair.v0`)

- 规格: Tuple **永不拍平** 硬约束 — 嵌套 Tuple / struct 直接元素保持嵌套类型与 `@get` 路径; 禁止与扁平 Tuple 等同或隐式 coerce (`spec_rules` / `syntax/type` / `memory` / `start_here`)

- 文档: 删除已 drain 的 `doc/todo_non_g6.md`; 后置/可选并入 `start_here` §5–§6 与 `roadmap_status`

- codegen: 修复纯标量 struct 在 field 反射循环内 `out = @field_set(...)` 写错 local
  - 根因: 循环 collect 把已有 `struct_locals` 的 reassignment 误收成 `__field_*_` shadow; 写 `$out.n` 而 return 读 shadow
  - 修: `collectBodyLocals` 对已登记 `struct_locals` 跳过 inferred struct rebinding
  - 正例: `ok/191_json_from_json_pure_scalar` (`compiled_must_pass`)

- JSON: struct 字段 `u8` stringify/from_json 重载 (`ok/190_json_struct_u8_field`; 混合 managed 字段路径)
- LSP: hover 对当前文件类型声明/引用返回类型名 head (`src/lsp/hover.zig`)
- 非 G6 todo 清单 drain: push-on-advance 协议 + §9 阻断登记; release smoke 绿- 非 G6 日路径: `UnsupportedTupleStorageLeaf` 专用诊断 + 文档漂移收口
  - 裸 struct 等非 packable 叶子 `[Tuple]` storage 从泛化 `UnsupportedLowering` 拆出独立 code/summary/hint
  - 历史反例 `compile_err/339` 已由 P1 收回 (现 `compile_ok/273` / `ok/193`)
  - 文档: README / start_here / master_plan / roadmap_status / spec_rules / syntax/type 对齐「managed 叶子与 path chain 已落地」

- I2 后置 lowering: managed/`text` 叶子 `[Tuple]` storage + `@get(storage,i,j)` path chaining
  - scheme A 扩展: managed payload 叶子 pack 为 4 字节 handle; 合成 `is_storage_pack` layout 负责 clone/free 叶子 ARC
  - path chain: storage 元素基址保留在 `$__tuple_pack_base_tmp`, 再按直接元素索引 load
  - 正例: `compile_ok/270`–`271`, `compiled_ok/75`–`77`

- 清理旧文档与占位; 目录重命名 `lib`/`src`; 架构扁平拆分; 文档规范化

### 验证

```text
cd src && zig test main.zig
  → All 119 tests passed.
./src/build/test/run_tests.sh
  → pass=915 fail=0 skip=3
./src/build/test/run_release_smoke.sh
  → release smoke passed
```
