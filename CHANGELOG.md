# Changelog

本文只记录**最近仍需可追溯**的已完成变更。实时停点见 `doc/start_here.md`; 总规划见 `doc/master_plan.md`。  
更早条目已从仓库移除, 需要时查 git 历史。

## 2026-07-12

- 清理旧文档与占位
  - 删除长期 ARC 草案与 TS 原型: `doc/arc.md`、`doc/arc*.ts`
  - 删除空占位: `src/test/`、`src/doc/`、`src/build/test/pending/`
  - 删除非主线样例: `ui.do`、`ui_demo.do`
  - 收缩 `doc/master_plan.md` / `doc/roadmap_status.md` / 本文件为**当前态 only** (不保留已完成阶段流水账)
  - 不保留向后兼容路径或旧入口

- 目录重命名: 标准库 `src` → `lib`, 工具链 `tool` → `src`
  - `@lib("file.do")` 根为 `lib/`; WASI `source=` / `__wasi_shim_lib_*`
  - 回归: `./src/build/test/run_tests.sh`; unit: `cd src && zig test main.zig`

- 架构重构五轮: `diagnostics` / `type_name` / `sema_error` / `codegen_payload_wat` / `codegen_storage_wat`
  - `UnsupportedLowering`; loop Tuple `@get`; fixture `269`/`74`/`339`/`340`

- 文档与计划规范化: `doc/start_here.md` 接手入口; README / AGENTS 路径对齐

### 验证

```text
cd src && zig test main.zig          → All 115 tests passed.
SKIP_BUILD=1 ./src/build/test/run_tests.sh → pass=907 fail=0 skip=3
```
