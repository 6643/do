# Changelog

本文只记录**最近仍需可追溯**的已完成变更。实时停点见 `doc/start_here.md`; 总规划见 `doc/master_plan.md`。  
更早条目已从仓库移除, 需要时查 git 历史。

## 2026-07-12

- codegen: pure-scalar 具名 struct 作为 Tuple storage **嵌套子槽** (永不拍平)
  - `items [Tuple<Point, u8>]` / `@put` / `@get` / path `@get(items, i, 0)` → `Point`
  - 局部 `Tuple` 槽用位置名 `$pair.0.x` / `$pair.0.y` / `$pair.1` (不是假字段 `v0`)
  - 含 managed 字段的 struct 槽仍 `UnsupportedTupleStorageLeaf` (`compile_err/339`)
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
  - 反例: `compile_err/339_tuple_non_packable_leaf_storage`
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
