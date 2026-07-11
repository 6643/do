# Changelog

本文只记录**最近仍需可追溯**的已完成变更。实时停点见 `doc/start_here.md`; 总规划见 `doc/master_plan.md`。  
更早条目已从仓库移除, 需要时查 git 历史。

## 2026-07-12

- 非 G6 日路径: `UnsupportedTupleStorageLeaf` 专用诊断 + 文档漂移收口
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
  → All 117 tests passed.
./src/build/test/run_tests.sh
  → pass=911 fail=0 skip=3
```
