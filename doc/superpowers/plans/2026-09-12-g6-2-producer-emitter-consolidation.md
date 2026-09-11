# G6.2 Producer Runtime Audit 实施计划

日期: 2026-09-12
状态: 方案 1（保持 WAT byte parity）已批准；本阶段已验证，不迁移 route

## 目标

在不改变既有 producer 产物和公开能力的前提下，完成 contract/runtime-layout、
canonical-to-frame binding 和 12 个现有 template 的 lifecycle 文本审计。共享 lifecycle
emitter、template decomposition 和 state IR 不在本计划实现，另立 deferred 设计。

## 全局约束

- 不改 WAT/WIT bytes、descriptor/WIT hash、diagnostic、runtime counter 或 GC capability
  inventory 语义；新增 test-only ARC 词面时，仅允许补对应的 `isolate_test_only` 分类行；
- 不删除、重写或替换任何 producer template；
- 不新增 `own<T>`、`borrow<T>`、`ref<T>`、generic producer admission 或 arbitrary
  producer expression；
- audit 模块只消费显式 measured facts，不读取 lexer/registry，不生成 WAT；
- `0` 是合法 offset/handle，缺失必须显式表达；
- 工具链 cache 缺失时记录阻断，使用仓库本地 cache 做可用验证，不修改系统工具链。

## 单元进度

### 1. 关闭 parity 决策门（已完成）

证据：现有 route 仍以完整 `@embedFile` template 为主，canonical payload offset 与
template frame offset/state facts 未形成可证明的通用映射，且已有 byte `cmp` gates。

裁定：本阶段保持 byte parity，只做 audit；shared emitter migration deferred。

验收：设计 spec 已记录依据、范围、非目标和 deferred gate。

### 2. 实现 runtime audit validator（已完成）

文件：

- `src/build/codegen_component_producer_runtime_audit.zig`
- `src/build/codegen_component_producer_runtime_audit_test.zig`
- `src/main.zig`（test root import）

实现并测试：

- frame size、field range、alignment、overlap；
- guest/transferred/released state 完整性和唯一性；
- post-transfer cancel state coverage；
- canonical payload 与 frame binding 边界；
- cleanup symbol、offset、stage 顺序；
- `validate_contract` 的 contract/runtime stage parity。

验收命令：

```bash
cd src
TMPDIR="$PWD/../.tmp/do-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
zig test main.zig --test-filter "producer runtime audit"
```

### 3. 审计现有 template（已完成）

覆盖 12 个 checked-in template，按真实模板分组检查 required fragments、lifecycle
order、layout markers 和 `__arc_` 禁止片段。不会把 record-only marker 套到 C-min list，
scalar list 使用其真实 `[producer-stream-item-slot]` marker。

验收：focused suite `14/14` 通过（使用仓库本地 Zig cache）。

### 4. 格式化与全量验证（已完成）

执行顺序：

```bash
zig fmt src/main.zig \
  src/build/codegen_component_producer_runtime_audit.zig \
  src/build/codegen_component_producer_runtime_audit_test.zig

cd src
TMPDIR="$PWD/../.tmp/do-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
zig test main.zig
zig build -Doptimize=ReleaseSmall
cd ..
./src/build/test/run_tests.sh
git diff --check
```

实际证据：

- `zig test main.zig`: `1596/1596`，退出码 `0`；
- `zig build -Doptimize=ReleaseSmall`: 退出码 `0`；
- `./src/build/test/run_tests.sh`: `14/14 steps; 53/53 tests passed`，退出码 `0`；
- ARC inventory: `rows=53 matches=490 unclassified=0 normal_route_matches=0`，生产依赖
  闭包 `modules=158 forbidden=0`；
- `git diff --check`: 已通过。

direct Rust ABI/equivalence 的独立 gate 仍受系统 Zig runtime archive cache 状态影响，
本阶段没有把该环境问题伪装成源码验证结果；harness 内的 Rust async runner 已通过。

### 5. 文档 closeout（已完成）

plan/spec 已收敛为 audit-only 目标，并记录实际全量输出、inventory row 变化和残余工具链
风险。不更新 master plan 或 capability matrix，因为本阶段不改变能力和 route。

残余风险：模板覆盖目前是显式列出的 12 个 `@embedFile`，未来新增模板不会自动进入审计；
`audit_template` 是 substring/order 检查，不能替代 WAT 解析或 runtime semantic gate；
binding 目前验证数值边界，不证明 frame offset 对应完整 field 区间。这些都属于 deferred
shared-emitter gate 的输入，不在本阶段扩大实现。

## Deferred backlog（不属于本阶段）

以下工作保持未开始状态，不得从 audit 结果推断完成：

1. template decomposition：把完整 embedded WAT 拆为可组合 payload/lifecycle fragments；
2. canonical-to-frame mapping：为每个 route 建立机器可验证的 offset/state fact table；
3. lifecycle state IR：覆盖 transfer commit、post-transfer cancel、reverse cleanup、
   nested/batched ownership 和 exactly-once counter；
4. shared emitter route migration：逐 route 做 byte/runtime/diagnostic gate，任何失败
   都保持旧 route，不允许 silent fallback；
5. generic producer admission、arbitrary producer expression、borrowed async payload、
   filesystem/HTTP async 扩展：另立公开设计和 gate。

Deferred 工作的启动条件：第 1-3 项都有独立失败测试和 mapping 证据，且重新批准
byte-parity 或 semantic-parity 的最终验收矩阵。

## 交付限制

本轮只提交本阶段相关的 2 个文档、inventory row、audit 实现、audit 测试和 test-root import。除非用户
另行明确要求，不在本计划内 commit/push，也不触碰无关 worktree 改动。
