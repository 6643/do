# Map、工具链适配与 Zig 测试编排 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 Do GC/值语义和 P3 Rust runtime 证据边界的前提下，加入 WIT `map<K,V>` 生命周期支持，集中工具链升级入口，并把仓库自有 Shell 测试编排迁移到 Zig。

**Architecture:** WIT map 在 `src/wit` 中作为独立类型解析，生成 Do `HashMap<K,V>`，canonical ABI 仍使用受 operation frame 约束的 pair-list。Zig 提供 current-only Toolchain Adapter 和 table-driven integration harness；Rust 保留 Wasmtime Component async/resource host runner。

**Tech Stack:** Zig 0.16.0、Do compiler、WIT parser/emitter、`wasm-tools 1.258.0`、Wasmtime CLI 48.0.1、Rust Wasmtime 48.0.1（通过门禁后锁定）、Cargo、WAT/WIT Component fixtures。

**Spec:** `doc/superpowers/specs/2026-08-30-map-toolchain-zig-harness-design.md`; `doc/superpowers/specs/2026-08-30-canonical-abi-operation-lifetime-design.md`

## Global Constraints

- 继续 current-only：active route 不支持旧版工具回退或双版本矩阵。
- 不修改 Do 的 GC、值语义、公开 `own<T>`/`borrow<T>`/`ref<T>` 设计。
- 不自动把 `list<tuple<K,V>>` 改写为 map。
- map key 只允许整数、`bool`、`char`、`string`；resource 和复合类型 key 必须拒绝。
- canonical `ptr,len` 不得跨 operation、Future suspension 或 Stream poll 边界逃逸。
- `.deps/wit-bindgen`、`.worktrees`、`.tmp`、生成的 Cargo `target` 和历史文档不属于改写范围。
- 每个任务完成后运行该任务列出的最小验证，再进入下一任务；共享的 `main` 工作区 dirty 改动不得 reset、checkout 或清理。

---

### Task 1: 固化三问题规格和基线

**Files:**
- Create: `doc/superpowers/specs/2026-08-30-map-toolchain-zig-harness-design.md`
- Create: `doc/superpowers/plans/2026-08-30-map-toolchain-zig-harness.md`
- Modify: `doc/superpowers/specs/2026-08-30-canonical-abi-operation-lifetime-design.md`
- Test: `git diff --check`

**Interfaces:**
- Consumes: 当前 WIT model、`lib/hash_map.do`、canonical ABI 生命周期设计。
- Produces: map、工具链 adapter、Zig harness 的不变量和非目标，供后续任务共同引用。

- [x] **Step 1: 补充 canonical lifetime 的 map 规则。**

  在 operation 类型表增加 map 输入、同步 result lift、async 参数和 Stream 排队四行，明确 pair-list 只是 ABI 表示，map payload 必须遵循 operation frame 释放点。

- [x] **Step 2: 运行规格一致性检查。**

  Run: `rg -n "map|operation frame|current-only|Zig.*Rust" doc/superpowers/specs/2026-08-30-map-toolchain-zig-harness-design.md doc/superpowers/specs/2026-08-30-canonical-abi-operation-lifetime-design.md`

  Expected: 三个主题都有目标、边界、非目标和验收条目；`git diff --check` 返回 0。

- [x] **Step 3: 保存基线证据。**

  Run: `wasm-tools --version && wasmtime --version && zig version && find examples/p3-runtime/rust-host-runner/src -type f -name '*.rs' | wc -l && find examples/p3-runtime -maxdepth 1 -type f -name '*.sh' | wc -l`

  Expected: 记录当前 CLI 版本、Zig 版本、Rust runner 数量和 P3 Shell 数量；不把这些数量写成语义完成声明。

### Task 2: 增加 WIT map model/parser 的失败测试

**Files:**
- Modify: `src/wit/tests.zig`
- Modify: `src/main.zig` (test aggregator only)
- Modify: `src/wit/model.zig`
- Modify: `src/wit/parser.zig`
- Test: `src/wit/tests.zig`

**Interfaces:**
- Consumes: WIT type parser 的 `TypeKind`、`TypeRef` 和现有 tuple/option/result 测试。
- Produces: `.map` kind、两参数 map type ref、非法 key/arity 的稳定错误。

- [x] **Step 1: 写 map 正例和负例测试。**

  在 `src/wit/tests.zig` 增加内存中的 WIT package：`f: func(values: map<string, u32>);`，断言参数 kind 为 `.map`、args 数量为 2、key kind 为 `.string`、value kind 为 `.u32`；再增加 `map<u32>`、`map<record-name, u32>` 和 `map<own<ticket>, u32>` 的拒绝测试。

- [x] **Step 2: 运行失败测试。**

  Run: `cd src && zig test wit/tests.zig --test-filter 'map'`

  Expected: 在 `.map` 尚未加入 model/parser 前失败，失败原因必须指向未知类型或未实现的 map，而不是测试语法错误。

- [x] **Step 3: 提交测试接口定义。**

  只保留测试所需的错误分类和断言，不扩大 WIT public API。

### Task 3: 实现 WIT map 解析、验证和 Do emitter 映射

**Files:**
- Modify: `src/wit/model.zig`
- Modify: `src/wit/parser.zig`
- Modify: `src/wit/emit_do.zig`
- Modify: `src/wit/signature.zig`
- Modify: `src/wit/resolve.zig`
- Modify: `src/main.zig` (test aggregator only)
- Test: `src/wit/tests.zig`

**Interfaces:**
- Consumes: Task 2 的 `.map` model contract。
- Produces: `map<K,V>` parse result；Do 输出 `HashMap<K,V>`；WIT signature 保留 `map<K,V>`；key/arity guard。

- [x] **Step 1: 增加 `TypeKind.map` 和 parser 分支。**

  解析 `map` 为恰好两个参数；参数数量不是 2 时返回现有 `InvalidTypeArity`；递归解析参数并保留 span、ownership 和 nested type refs。

- [x] **Step 2: 增加 key guard。**

  添加纯函数 `map_key_allowed(type_ref)`，只接受整数、`bool`、`char`、`string`；遇到 named resource、own、borrow、record、variant、list、tuple、future、stream 时返回现有拒绝错误。

- [x] **Step 3: 映射生成结果。**

  `emit_do.zig` 将 map 输出为 `HashMap<key, value>`；`signature.zig` 输出 WIT 形态 `map<key, value>`；不得把 list/tuple 的既有输出改写为 map。

- [x] **Step 4: 运行 WIT 测试。**

  Run: `cd src && zig test wit/tests.zig --test-filter 'map'`

  Expected: map 正例、arity 负例、非法 key 负例全部通过；已有 tuple/list/option/result 测试保持通过。

### Task 4: 接通 manifest、marshal registry 和 map ABI 生命周期测试

当前状态（2026-08-30）：manifest/registry 的 map schema 与 pair-list 事实已
落地并通过单元及标准回归；通用 map Component lowering 尚不存在，因此真实
同步 lift、异步 copy、Stream 跨 poll 的运行时 gate 暂缓，避免把静态元数据
误报为运行时能力。

**Files:**
- Modify: `src/wit/marshal_registry.zig`
- Modify: `src/wit/manifest.zig`
- Modify: `src/wit/descriptor_manifest.zig`
- Modify: `src/wit/emit_manifest.zig`
- Modify: `src/wit/manifest_test.zig`
- Modify: `src/wit/descriptor_manifest_test.zig`
- Create: `src/build/test/compile_ok/746_wit_map_binding.do`
- Create: `src/build/test/compile_err/746_wit_map_resource_key.do`
- Create: `src/build/test/compile_err/746_wit_map_resource_key.expect`
- Create: `examples/p3-runtime/wit/map-lifetime-probe.wit`
- Create: `examples/p3-runtime/map-lifetime-probe.wat`
- Create: `examples/p3-runtime/test_wit_map_lifetime.sh` (temporary gate, later called by Zig harness)

**Interfaces:**
- Consumes: Task 3 map type and `doc/superpowers/specs/2026-08-30-canonical-abi-operation-lifetime-design.md`。
- Produces: manifest map shape represented as pair-list ABI; sync lift, async copy and Stream owned-buffer assertions。

- [x] **Step 1: 写 manifest 和 lifetime red tests。**

  已增加 manifest map schema/pair-list 断言、descriptor map ABI 解析和非法
  复合 key 拒绝测试。真实 lifecycle fixture 保留到通用 map lowering 可用后。

  manifest test 断言 map 的 key/value schema 和 pair-list canonical representation；fixture 断言同步 result lift 后仍可读取 GC `HashMap`，异步和跨 poll 场景不读取已释放的 input span。

- [x] **Step 2: 运行 red gate。**

  先观察到 `Document.maps`、`Descriptor.map_abi` 缺失导致的预期编译失败，
  实现后由 `zig test main.zig --test-filter 'map'` 覆盖并通过。

  Run: `cd src && zig test wit/manifest_test.zig --test-filter 'map' && zig test wit/descriptor_manifest_test.zig --test-filter 'map'`

  Expected: 在 registry/manifest 尚未支持 map 时失败，失败点为未登记 shape，而不是静默降级为 list。

- [x] **Step 3: 实现 registry/manifest map shape。**

  将 map 的 ABI shape 记录为 `list<pair<key,value>>`，保留 map 语义标识、key/value 类型和 WIT hash；禁止把 map resource key 标记为可接受。

- [ ] **Step 4: 实现四条生命周期路径。**

  阻断：`src/build/wit_abi_types.zig` 和当前 marshal WAT emitter 没有通用
  map/pair-list ABI 节点与构造路径。当前 registry 对 map 明确返回
  `UnsupportedWitMarshalShape`；在新增 ABI lowering、边界拷贝和 cleanup
  authority 之前不得创建通过型 runtime gate。

  fixture 覆盖同步输入、同步 result lift、async input copy、Stream 跨 poll owned buffer；每条路径都要求错误、取消、drop 和 Store disposal 只释放一次。

- [ ] **Step 5: 运行 focused map gate。**

  依赖 Step 4；目前仅验证 wasm-tools 1.258.0 能解析 map WIT 并生成
  pair-list 形态的 component metadata，尚无 Do map runtime 结果证据。

  Run: `bash examples/p3-runtime/test_wit_map_lifetime.sh`

  Expected: WIT parse、Core parse、Component validate、map result、async copy、stream buffer 和 cleanup marker 全部通过；非法 resource-key fixture 返回预期诊断。

### Task 5: 建立 current-only Zig Toolchain Adapter

**Files:**
- Create: `toolchain/toolchain.lock.json`
- Create: `src/build/toolchain.zig`
- Create: `src/build/toolchain_cli.zig`
- Modify: `src/build.zig`
- Create: `src/build/test/toolchain_adapter_test.zig`
- Modify: `src/build/test/check_gc_default_build_gate.sh`
- Modify: `examples/p3-runtime/test_wasm_tools_current_only.sh`
- Modify: `examples/p3-runtime/assemble_async_component.sh`

**Interfaces:**
- Consumes: 当前 wasm-tools/Wasmtime CLI、Task 1 的 current-only 决策。
- Produces: `bin/do-toolchain` 命令和 typed operations：`parse-core`、`strip-core`、`embed-component`、`new-component`、`validate-component`、`component-wit`、`print-component`、`run-wasmtime`、`probe`。

- [x] **Step 1: 写 adapter 失败测试。**

  `toolchain_adapter_test.zig` 使用 fake executable 验证：版本错误、hash 错误、缺少能力和子命令非零退出都 fail-closed；正确版本和能力返回结构化结果。

- [x] **Step 2: 运行失败测试。**

  Run: `cd src && zig test build/test/toolchain_adapter_test.zig`

  Expected: adapter API 尚未存在时失败。

- [x] **Step 3: 写单一 lock。**

  在 `toolchain/toolchain.lock.json` 记录本机实测 `wasm-tools 1.258.0`、`wasmtime 48.0.1`、Zig 0.16.0、Rust/Cargo 版本、revision 和 SHA-256；Rust crate 版本字段在其编译门禁通过前保持显式 pending 状态，不允许隐式混用。

- [x] **Step 4: 实现 typed command runner。**

  `src/build/toolchain.zig` 负责读取 lock、解析版本/hash、运行子进程、捕获 stdout/stderr 和退出码；每个命令只接受声明好的参数，不提供任意 passthrough。

- [x] **Step 5: 安装 Zig CLI。**

  在 `src/build.zig` 增加 `do-toolchain` executable 和安装目标；CLI 把 typed operation 映射到当前工具的命令行，不让 compiler semantic modules 读取版本号。

- [x] **Step 6: 迁移 current-only gate。**

  将 `check_gc_default_build_gate.sh` 和 `assemble_async_component.sh` 的版本/hash/parse/embed/new/validate 调用改为 `bin/do-toolchain`；历史文档不改写。

- [x] **Step 7: 运行 adapter focused gates。**

  Run: `cd src && zig test build/test/toolchain_adapter_test.zig && ../bin/do-toolchain probe`

  Expected: probe 输出当前版本、hash 和 capability JSON；错误版本、错误 hash、缺少 capability 均以非零退出结束。

### Task 6: 升级并收敛 Rust Wasmtime host runner

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.lock`
- Modify: only Rust files that fail against the selected Wasmtime API
- Test: `examples/p3-runtime/rust-host-runner/src/**/*.rs`

**Interfaces:**
- Consumes: Task 5 adapter 的 Wasmtime version/capability record。
- Produces: 一个明确锁定的 Rust Wasmtime runtime oracle；不改变 host runner 对外 marker 和 cleanup contract。

- [x] **Step 1: 固定 Rust 升级失败基线。**

  Run: `cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml`

  Expected: 记录现有 47.0.2 构建结果和升级前 API 使用点；不得把 Cargo target 产物加入 git。

- [x] **Step 2: 将 crate 锁到 48.0.1。**

  修改 `Cargo.toml` 的 Wasmtime 版本并用 `cargo update --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml --precise 48.0.1` 更新 lock；不升级无关依赖。

- [x] **Step 3: 逐个修复 API 编译错误。**

  仅调整 Wasmtime 48.0.1 所需的 API、feature 或错误类型；保留 `Accessor`、`func_wrap_concurrent`、`run_concurrent`、resource table 和生命周期 marker。

- [x] **Step 4: 运行 Rust focused matrix。**

  Run: `cargo test --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml` 和现有 `test_rust_*.sh` gates（通过 `bin/do-toolchain` 调用工具）。

  Expected: async ready/pending/error/cancel/drop、resource transfer、stream 和 Store disposal marker 与升级前契约一致。代表性 wait-for/resource/StreamMirror gates 已通过；仍直接硬编码旧 wasm-tools 版本的脚本留给 Task 8 迁移。

### Task 7: 建立 Zig integration harness

**Files:**
- Create: `src/build/test/process.zig`
- Create: `src/build/test/test_harness.zig`
- Create: `src/build/test/test_cases.zig`
- Modify: `src/build.zig`
- Modify: `src/build/test/run_tests.sh`（迁移期间仅保留启动入口）
- Test: `src/build/test/test_harness.zig`

**Interfaces:**
- Consumes: Task 5 `do-toolchain` typed operations和 Task 6 Rust runner binary names。
- Produces: `zig build test` 集成入口；统一 process result、temporary directory、timeout、cleanup 和 assertion contract。

- [x] **Step 1: 写 process helper 失败测试。**

  覆盖成功退出、非零退出、stdout/stderr 捕获、环境变量注入、超时终止和临时目录清理；测试使用本地 fake executable，不触碰真实 Component。

- [x] **Step 2: 运行失败测试。**

  Run: `cd src && zig test build/test/process.zig`

  Expected: helper 尚未实现时失败。

- [x] **Step 3: 实现 typed process helper。**

  提供 `run_checked(argv, env, timeout_ms)`、`make_temp_dir()`、`assert_stdout_contains()`、`assert_stderr_contains()` 和 `defer_cleanup()`；错误包含 argv、退出码和脱敏后的 stderr。

- [x] **Step 4: 建立 table-driven cases。**

  `test_cases.zig` 为 compiler ok/err、Core GC、Component assembly、map lifetime、Rust host runner 定义路径、命令、预期退出码和 marker；所有 wasm-tools/Wasmtime 调用只能通过 adapter。

- [x] **Step 5: 接入 `zig build test`。**

  在 `src/build.zig` 增加 `test` step：先构建 `do` 和 `do-toolchain`，再运行 harness；保留 `SKIP_BUILD`、`RUN_WASM` 等现有环境变量语义，但由 Zig 显式解析。

- [x] **Step 6: 运行 harness focused matrix。**

  Run: `cd src && zig build test --summary all`

  Expected: 至少覆盖 compiler smoke、一个 WIT map、一个 Component assembly、一个 Rust async runner；失败时报告具体 case 和原始退出信息。

### Task 8: 分批迁移仓库自有 Shell 测试

**Files:**
- Modify: `src/build/test/run_tests.sh`
- Modify: `examples/gc-p3-runtime/*.sh`（仅当前 GC 测试入口）
- Modify: `examples/p3-runtime/*.sh`（按批次迁移）
- Modify: `examples/wit-bindgen-do/*.sh`（仅仓库自有 gate）
- Test: `src/build/test/test_harness.zig`

**Interfaces:**
- Consumes: Task 7 harness；现有脚本中的 fixture、marker、negative diagnostic、Cargo runner 参数。
- Produces: Zig table-driven cases 覆盖同等验收；Shell 不再重复实现工具调用和清理逻辑。

- [ ] **Step 1: 迁移编译器和 GC 批次。**

  先迁移 `src/build/test/run_tests.sh` 中的 compiler ok/err、format、LSP、GC fixture 和 `examples/gc-p3-runtime`，逐个保留原退出码、marker、negative diagnostic 和 skip 语义。

  **实施 checkpoint (2026-08-30):** Zig harness 已接入 compiler fixture
  (`ok/err/compile_ok/compile_err`)、`run`、`fmt`、`check`、LSP 九个 fixture，
  以及 `examples/gc-p3-runtime` 中 86 个默认 GC `.do` fixture；`RUN_WASM=1`
  时还覆盖 2 个 compiled-trap fixture。GC route 已保留
  ARC 残留、GC marker、scalar call-chain/control-flow marker、WAT 生成和
  `do-toolchain parse-core` 检查；旧 `check_gc_default_build_gate.sh` 对等基线为
  `86 fixtures`，旧 `run_tests.sh` 基线为 `pass=1446 fail=0 skip=3`，新版
  `zig build test --summary all` 为 `10/10` build steps、`6/6` tests。该 step
  仍未勾选：`examples/gc-p3-runtime` 的专用脚本矩阵、旧 Shell 入口的逻辑缩减
  和逐脚本对等报告留到本 step 后续批次，当前不删除或绕过旧入口。

  **实施 checkpoint (2026-08-31 GC adapter):** `test_do_gc_*.sh` 的 59 个
  GC fixture gate 已全部使用 current-only `bin/do-toolchain`；Core parse、GC
  compile/invoke/run 均由 typed operations 承接，并锁定
  `toolchain/toolchain.lock.json`。59/59 在仓库根目录和无关 `/tmp` cwd 均通过，
  `bash -n`、旧工具调用扫描、adapter 单元测试和 `git diff --check` 均通过。
  报告位于
  `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step1-gc-adapter-report.md`。
  Step 1 仍未勾选：`run_tests.sh` 的其他逻辑和完整旧 Shell 入口收敛仍待完成。

- [ ] **Step 2: 迁移纯 assembly/validation 批次。**

  再迁移 `examples/p3-runtime` 中只执行 `do`、parse、embed、new、validate、WIT/hash 检查的脚本；命令全部改为 adapter operation。

 **实施 checkpoint (2026-08-30):** Zig harness 已增加 assembly validation
 case，覆盖 `assemble_async_component.sh` 的 current-only marker、产物存在、
 adapter validate 和 probe identity；另增加 WIT snapshot validation，使用 Zig
 原生 SHA-256 校验 `p3-clocks-manifest.json`，并通过 adapter `component-wit`
 校验 clocks package/member 与 resource-probe 的 `ticket` resource。
 首批及后续批次共纳入 23 个 pure lowering case，覆盖 async-call/host、CLI
 streams、HTTP empty request、async/owned-error Result、resource probe、
 record stream、StreamMirror、descriptor-owned reader/writer、filesystem
 preopen/read-directory（含 bounded）以及 G6.2 C-min/dynamic/batched/
 scalar-list producer；对应 Shell gates 已在当前工具链下复跑通过。
 新增 `do-toolchain validate-core` 固定操作承接 Core GC validation，锁定
 `gc,cm-async,cm-more-async-builtins` feature 集合；
 `test_do_async_host_scalar_argument.sh` 已移除旧版 wasm-tools 断言并改走
 current-only adapter。Step 2 仍未完成，剩余 package-output、variant/nested
 producer 的专用 assembly 脚本待逐批归并。

**实施 checkpoint (2026-08-31):** lifecycle pure adapter 子批次完成：
`test_do_owned_error_result_lowering.sh`、
`test_do_resource_cancellation_shape.sh`、
`test_do_stream_mirror_lowering.sh`、
`test_do_cli_stream_stdin_lowering.sh`、
`test_do_borrowed_resource_rejection.sh` 已统一使用 `bin/do-toolchain`，并在
根目录及无关 cwd 各 5/5 通过；保留原有 marker、负例诊断和 GC Core
validation 语义。批次报告位于
`.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step2-lifecycle-pure-adapter-report.md`。
该 checkpoint 不代表 Step 2 全部完成；其余 direct-tool gate 仍待迁移。

**实施 checkpoint (2026-08-31 sockets):**
`test_do_wasi_sockets_create_bind_drop.sh` 已移除旧 wasm-tools 版本检查，
TCP/UDP 的 parse、embed、new、validate 全部改走 `bin/do-toolchain`；根目录和
无关 cwd 各 1/1 通过。Zig pure matrix 新增 TCP/UDP 两个 case，验证协议专属
create/bind/drop marker 和反协议禁止 marker；focused harness 4/4、完整
`zig build test --summary all` 为 12/12 steps、21/21 tests。该 checkpoint
仍不代表 Step 2 全部完成，metadata-only `component embed -t` 等 direct-tool
 路径需要后续新增 typed adapter operation。

**实施 checkpoint (2026-08-31 filesystem component):**
`test_do_wasi_filesystem_get_flags.sh` 与 `test_do_wasi_filesystem_stat.sh`
的 Core parse、Component embed/new、validate，以及 stat 的 print/component
WIT 提取均已改用 `bin/do-toolchain`；根目录和无关 cwd 各 2/2 通过，语法、
current-only guard、scoped diff check 均通过。get-flags 的负例断言同步到
当前 compile_err 期望（未注册 descriptor 为 `UnsupportedP3AsyncComponent`，
错误结果/借用 payload 为 `P3AsyncHostSignatureMismatch`）。本 checkpoint
仅关闭该两脚本子批次，Task 8 Step 2 仍有其他 direct-tool gate。

**实施 checkpoint (2026-08-31 filesystem ABI):**
`test_d2_wasi_filesystem_get_type_abi.sh`、
`test_d2_wasi_filesystem_get_flags_abi.sh` 与
`test_d2_wasi_filesystem_sync_abi.sh` 已将 metadata-only `component embed -t`
以及 parse/embed/new/validate/print/component-wit 全部改为
`bin/do-toolchain` typed operations；根目录和无关 cwd 各 3/3 通过，语法、
direct-tool scan、current-only guard、scoped diff check 均通过。旧版
1.255.0 identity guard 是三脚本迁移前的 RED。本 checkpoint 仅关闭该三脚本
子批次，Task 8 Step 2 仍有其他 direct-tool gate。

实施 checkpoint (2026-08-31 remaining filesystem ABI):
test_d2_wasi_filesystem_open_at_abi.sh、
test_d2_wasi_filesystem_set_size_abi.sh、
test_d2_wasi_filesystem_stat_abi.sh、
test_d2_wasi_filesystem_stat_at_abi.sh 与
test_d2_wasi_filesystem_sync_data_abi.sh 已将 metadata-only component
embed -t、Core parse/validate、Component embed/new/validate/print/component-wit
全部改为 current-only bin/do-toolchain typed operations；根目录和无关 /tmp cwd
各 5/5 通过，bash -n、direct-tool scan、current-only guard、scoped git
diff --check 均通过。本 checkpoint 仅关闭该五脚本子批次，Task 8 Step 2
仍有其他 direct-tool gate。

实施 checkpoint (2026-08-31 async-call):
test_do_async_call_component.sh、test_do_async_call_inline_scalar_argument.sh
与 test_do_async_call_scalar_argument.sh 已将 Core parse 改为 current-only
bin/do-toolchain 的 parse-core，并移除旧 WASM_TOOLS 传递；根目录和无关 /tmp
cwd 各 3/3 通过，bash -n、legacy-tool scan、current-only guard、scoped
git diff --check 均通过。本 checkpoint 仅关闭该三脚本子批次，Task 8 Step 2
仍有其他 direct-tool gate。

**实施 checkpoint (2026-08-31 filesystem metadata-hash ABI):**
`test_d2_wasi_filesystem_metadata_hash_abi.sh` 与
`test_d2_wasi_filesystem_metadata_hash_at_abi.sh` 已将 metadata-only
`component embed -t`、Core parse/validate、Component embed/new/validate/print/
component-wit 全部改为 current-only `bin/do-toolchain` typed operations；根目录
和无关 `/tmp` cwd 各 2/2 通过，`bash -n`、direct-tool scan、current-only guard、
scoped `git diff --check` 均通过。迁移初次运行还暴露并修复了 metadata-hash
assembly helper 缺失的局部 `core_wasm` 绑定。本 checkpoint 仅关闭该两脚本子批次，
Task 8 Step 2 仍有其他 direct-tool gate。

**实施 checkpoint (2026-08-31 async-call raw-component probes):**
`test_async_call_arg_probe.sh` 与 `test_async_call_scalar_argument_probe.sh` 的
Core parse、metadata-only embed、strip、print、custom WAT parse、Component
new 和 validate 已全部改为 current-only `bin/do-toolchain` typed operations。
为保留 `wasm-tools strip -a` 的固定语义，adapter 新增 `strip-core <input>
-o <output>`，映射为 `strip -a <input> -o <output>`，并在 lock capability 中登记。
两脚本在根目录和无关 `/tmp` cwd 各 2/2 通过，`bash -n`、目标文件 direct-tool
scan 与 `git diff --check` 均通过。该 checkpoint 仅关闭本两个 probe 子批次，
Task 8 Step 2 仍有其他 pure/Rust direct-tool gate。

  **实施 checkpoint (2026-08-31 source WIT verification):**
`verify_p3_wit.sh`、`verify_resource_probe_wit.sh` 与 `test.sh` 的 source-WIT
读取已统一改为 current-only `bin/do-toolchain component-wit`；WIT hash、package/
member/resource、C API host-drive queue 与退出码断言保持不变。三脚本在根目录和
无关 `/tmp` cwd 均通过，`bash -n`、目标 direct-tool scan 与入口完整行为回归均
通过。本 checkpoint 仅关闭 source-WIT 子批次，Task 8 Step 2 仍有其他 pure/Rust
  direct-tool gate。

**实施 checkpoint (2026-08-31 borrow capability matrix):**
`test_borrow_capability_matrix.sh` 的 Core parse、Component embed/new 及
borrow shape 负例已改用 current-only `bin/do-toolchain` typed operations。
direct、record、variant、list、future-owned、stream-owned 六个 accepted shape
以及 stream/future 两个 rejected-at-embed shape，在根目录和无关 `/tmp` cwd
均通过；`bash -n` 与目标 direct-tool scan 通过。本 checkpoint 仅关闭 borrow
capability 子批次，Task 8 Step 2 仍有其他 pure/Rust direct-tool gate。

**实施 checkpoint (2026-08-31 Rust async host scalar):**
`test_rust_async_host_scalar_argument.sh` 的 Core parse、Component embed/new、
validate 已改用 current-only `bin/do-toolchain`；Rust/Wasmtime runner、ready/
pending/cancel 三模式、scalar argument 与 drop/table lifecycle 断言保持不变。
根目录和无关 `/tmp` cwd 均通过，`bash -n`、目标 direct-tool scan 与完整三模式
验证均通过。本 checkpoint 仅关闭该 Rust host 子批次，Task 8 Step 3 仍有其他
Rust gate。

**实施 checkpoint (2026-08-31 Rust async resource/future-owned):**
`test_rust_async_resource_result.sh` 与 `test_future_owned_canonical_abi.sh`
已将 Core parse、Component embed/new、validate 和 component-wit 提取统一改为
current-only `bin/do-toolchain`；后者移除过期的 1.255.0 identity guard，使用
`core-gc-async` profile。两个脚本在根目录和无关 `/tmp` cwd 各 2/2 通过，保留
pending/immediate/error、ready/pending/cancel、canonical offset 与 exactly-once
cleanup marker；`bash -n`、目标 direct-tool scan 和 `git diff --check` 均通过。
报告位于 `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-async-resource-future-owned-adapter-report.md`。
该 checkpoint 仅关闭两个 Rust host 子批次，Task 8 Step 3 仍有其他 Rust gate。

**实施 checkpoint (2026-08-31 Rust filesystem/socket runtime):**
六个 Rust/Wasmtime gate
`test_rust_wasi_filesystem_read_directory.sh`、
`test_rust_wasi_filesystem_read_directory_bounded.sh`、
`test_rust_wasi_filesystem_read_directory_real.sh`、
`test_rust_wasi_filesystem_preopen.sh`、
`test_rust_wasi_filesystem_real.sh` 与
`test_rust_wasi_sockets_real.sh` 已统一使用 current-only `bin/do-toolchain`；
async read-directory 使用 `component-async`，同步 filesystem/socket 使用 `none`。
六脚本在根目录和无关 `/tmp` cwd 各 6/6 通过，`bash -n`、direct-tool scan 与
`git diff --check` 均通过，原有 I/O、完成模式、失败模式和 cleanup marker 保持。
报告位于 `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-filesystem-socket-adapter-report.md`。
该 checkpoint 仅关闭六个 Rust host 子批次，Task 8 Step 3 仍有其他 Rust gate。

**实施 checkpoint (2026-08-31 Rust CLI streams):**
`test_rust_cli_stream_stdin.sh`、`test_rust_cli_stream_stdin_real.sh`、
`test_rust_cli_stream_stdout_budget_adapter.sh` 与
`test_rust_cli_stream_stdout_scheduler.sh` 已统一使用 current-only
`bin/do-toolchain`；stdin/stdout budget gate 使用 `component-async`，scheduler
继续复用 adapter-backed assembly。四脚本在根目录和无关 `/tmp` cwd 各 4/4
通过，`bash -n`、direct-tool scan 与 `git diff --check` 均通过，保留 WIT
mutation、budget/scheduler、stream/future cleanup marker。报告位于
`.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-cli-stream-adapter-report.md`。
该 checkpoint 仅关闭四个 Rust host 子批次，Task 8 Step 3 仍有其他 Rust gate。

**实施 checkpoint (2026-08-31 Rust G6.2 producers):**
五个 G6.2 Rust producer gate
`test_rust_g6_2_batched_list_resource_producer.sh`、
`test_rust_g6_2_c_min_dynamic_list_producer.sh`、
`test_rust_g6_2_c_min_list_resource_producer.sh`、
`test_rust_g6_2_owned_record_producer.sh` 与
`test_rust_g6_2_scalar_list_producer.sh` 已统一使用 current-only
`bin/do-toolchain`；所有 async Component 组装使用 `component-async` profile，
动态/取消变体也通过 adapter。五脚本在根目录和无关 `/tmp` cwd 各 5/5 通过，
`bash -n`、direct-tool scan 与 `git diff --check` 均通过，保留 layout、WIT、
ready/pending/error/cancel/early-drop 和 exactly-once cleanup marker。报告位于
`.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-g6-2-producer-adapter-report.md`。
该 checkpoint 仅关闭五个 Rust host 子批次，Task 8 Step 3 仍有其他 Rust gate。

**实施 checkpoint (2026-08-31 Rust filesystem ABI runtime):**
六个 filesystem ABI Rust gate
`test_rust_wasi_filesystem_metadata_hash.sh`、
`test_rust_wasi_filesystem_metadata_hash_at.sh`、
`test_rust_wasi_filesystem_open_at.sh`、
`test_rust_wasi_filesystem_set_size.sh`、
`test_rust_wasi_filesystem_stat.sh` 与
`test_rust_wasi_filesystem_stat_at.sh` 已移除旧 1.255.0 identity guard，并将
Core parse、Component embed/new/validate 全部改为 current-only
`bin/do-toolchain`；set-size 保留 Core validation。六脚本在根目录和无关
`/tmp` cwd 各 6/6 通过，`bash -n`、direct-tool/legacy guard scan 与
`git diff --check` 均通过，WIT/core hash、filesystem Result/cancel/drop 与
Store-disposal marker 保持。报告位于
`.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-filesystem-abi-runtime-adapter-report.md`。
该 checkpoint 仅关闭六个 Rust host 子批次，Task 8 Step 3 仍有其他 Rust gate。

**实施 checkpoint (2026-08-31 component-targets and owned-record equivalence):**
新增 typed `component-targets <wit> <component> --world <world>` adapter
operation，并将 `test_do_future_owned_component.sh` 与六个 G6.2 owned-record
equivalence/ABI gate 改为 current-only `bin/do-toolchain`；七个绿色 gate 在
根目录和无关 `/tmp` cwd 各 7/7 通过，`bash -n`、legacy direct-tool scan 与
scoped `git diff --check` 均通过。报告位于
`.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step2-component-targets-owned-record-report.md`。
`test_core_async_template.sh` 同步迁移 `new-component` 和 `component-targets`，
但下游 Rust wait-for 在 direct 与 adapter 产物上均以相同 SHA-256 和 exit 1
backtrace 失败，按既有 runtime blocker 保留，未计入绿色 gate。Task 8 Step 2
仍有其他 direct-tool gate。

**实施 checkpoint (2026-08-31 stream and borrow):**
`test_list_borrow_canonical_abi.sh`、`test_rust_stream_mirror.sh` 与
`test_rust_stream_reader_descriptor.sh` 已将 Core parse、Component
embed/new/validate 和 WIT 提取统一改为 current-only `bin/do-toolchain`，并
分别锁定 `none` 与 `component-async` profile。三脚本在根目录和无关 `/tmp`
cwd 各 3/3 通过，`bash -n`、目标 direct-tool scan 与 scoped
`git diff --check` 均通过；borrow pointer/stride、stream mode/drop/EOF
marker 保持。报告位于
`.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step2-stream-borrow-adapter-report.md`。
Task 8 Step 2 仍有 HTTP custom-WIT package 等 direct-tool gate。

**实施 checkpoint (2026-08-31 HTTP custom-WIT package):**
`test_http_payload_error_abi.sh` 与 `test_http_service_abi_surface.sh` 已将
custom-WIT package 的 Core parse、Component embed/new/validate 和 WIT 提取
统一改为 current-only `bin/do-toolchain`；payload 显式使用
`component-async`，service template/minimal/generated 使用 `none` 以保持原始
feature 语义。两脚本在根目录和无关 `/tmp` cwd 各 2/2 通过，`bash -n`、目标
direct-tool scan 与 scoped `git diff --check` 均通过；Result/DNS、service
WIT、Rust runtime 与 `table-empty=true` marker 保持。报告位于
`.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step2-http-package-adapter-report.md`。
Task 8 Step 2 仍有 GC、C API 边界和 WIT-bindgen-do 等剩余入口。

**实施 checkpoint (2026-08-31 wit-bindgen-do):**
`examples/wit-bindgen-do` 的四个生成 async/scalar/i64 gate 已将 Core parse、
Component embed/new/validate 统一改为 current-only `bin/do-toolchain`，显式
使用 `component-async` profile；根目录和无关 `/tmp` cwd 各 4/4 通过，
`bash -n`、目标 direct-tool scan 与 scoped `git diff --check` 均通过。生成 WIT、
manifest fail-closed、Rust pending/ready/cancel 与 cleanup marker 保持。报告
位于
`.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step2-wit-bindgen-do-adapter-report.md`。
Task 8 Step 2 剩余主要为 GC fixture、C API linker 边界和文本/历史检查。

**实施 checkpoint (2026-08-31 auxiliary smoke):** `src/build/test/run_wasm_smoke.sh` 与
`src/build/test/run_release_smoke.sh` 的 WAT parse 已统一改用 current-only
`bin/do-toolchain parse-core`，并导出 `DO_TOOLCHAIN_LOCK`；原有 Node 执行、发布
smoke 阶段、退出码和输出 marker 保持。`run_wasm_smoke.sh` 6/6 通过，
`run_release_smoke.sh` 全部阶段通过，`bash -n` 和 scoped direct-call scan 均通过。
该 checkpoint 仅关闭两个辅助 smoke 入口，Task 8 Step 2 仍有 GC/旧
`run_tests.sh` 逻辑和历史检查待处理；C API 脚本仍属于非 CLI linker 边界。

**实施 checkpoint (2026-08-31 run-tests parse):** 旧 `src/build/test/run_tests.sh`
中的 5 个 Core WAT parse 路径（compiled must-pass、compiled ok/trap、WASI
core shims 和 component-input shims）已改用 `bin/do-toolchain parse-core`，并
继承锁定的 `DO_TOOLCHAIN_LOCK`；其余 component WIT/embed/new/validate 分支仍
保留到 typed operation 能表达原始 world/package 语义后再迁移。完整旧入口以
  `SKIP_BUILD=1` 运行仍为 `pass=1446 fail=0 skip=3`，因此本批次未改变覆盖。

  **实施 checkpoint (2026-09-01 nested/managed GC manifests):** nested record
  lift/lower 的基础、三层和四层 manifest host/equivalence 共 12 个 gate，及
  managed-field record lift/lower（含 compiler、manifest、multi-field）共 12 个
  gate，均统一使用 current-only `bin/do-toolchain` 和锁定的
  `toolchain/toolchain.lock.json`；parse/embed/new/validate 分别映射到 typed
  operation，保留 manifest hash、GC/ARC equivalence、WAT layout、Rust host 和
  cleanup 断言。24/24 脚本在仓库根目录和无关 `/tmp` cwd 通过，`bash -n`、旧
  工具残留扫描和 scoped `git diff --check` 通过。该 checkpoint 仅关闭本批
  manifest/managed gate；nested compiler 变体、其余 GC direct-tool 入口及
  `run_tests.sh` 逻辑收敛仍待后续批次。

- [x] **Step 3: 迁移 Rust host 批次。**

  最后迁移调用 `cargo run` 的脚本；Zig harness 只负责准备 Component、传参和比对 marker，Rust 仍负责 runtime 行为。

  **实施 checkpoint (2026-08-31 owned-record producers):**
  `test_rust_g6_2_owned_record_nested_producer.sh`、
  `test_rust_g6_2_owned_record_pair_parameterized_producer.sh`、
  `test_rust_g6_2_owned_record_pair_producer.sh`、
  `test_rust_g6_2_owned_record_triple_producer.sh` 及其
  `test_g6_2_owned_record_triple_producer_abi.sh` 已统一使用 current-only
  `bin/do-toolchain`。triple 变体移除旧版 1.255.0 identity guard，并将
  parse/embed/new/validate 映射到 `component-async` profile；根目录和无关
  `/tmp` cwd 的 5/5 脚本均通过，保留 10-mode producer lifecycle、record
  layout、resource transfer 和 exactly-once cleanup marker。报告位于
  `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-owned-record-triple-adapter-report.md`。
  该 checkpoint 仅关闭 owned-record producer 子批次，Step 3 仍有 HTTP、
  record-stream、stream-writer、Result 等 Rust gate 待迁移。

  **实施 checkpoint (2026-08-31 HTTP request/cancellation):**
  `test_rust_http_payload_cancellation.sh`、
  `test_rust_http_payload_cancellation_dns_error_probe.sh`、
  `test_rust_http_request_body.sh`、
  `test_rust_http_request_body_await_completion.sh`、
  `test_rust_http_request_body_producer.sh`、
  `test_rust_http_request_empty.sh` 与
  `test_rust_http_service_empty_request.sh` 已统一使用 current-only
  `bin/do-toolchain` 的 `parse-core`、`embed-component`、`new-component` 和
  `validate-component`，并锁定 `component-async` profile。7/7 脚本在根目录和
  无关 `/tmp` cwd 通过，保留 payload cancellation、DNS discard、body
  producer/await、empty request 以及 Rust cleanup marker。报告位于
  `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-http-request-cancellation-adapter-report.md`。
  该 checkpoint 仅关闭 HTTP request/cancellation 子批次，Step 3 仍有
  response、record-stream、stream-writer、Result 等 Rust gate 待迁移。

  **实施 checkpoint (2026-08-31 HTTP response body):**
  `test_rust_http_response_consume_body.sh`、
  `test_rust_http_response_consume_body_await_trailers.sh`、
  `test_rust_http_response_consume_body_eof.sh`、
  `test_rust_http_response_consume_body_read.sh`、
  `test_rust_http_response_consume_body_two_read.sh` 与
  `test_rust_http_response_consume_body_three_read.sh` 已统一使用
  current-only `bin/do-toolchain` 的 typed parse/embed/new/validate 操作，
  并锁定 `component-async` profile。6/6 脚本在根目录和无关 `/tmp` cwd
  通过，保留 response bytes、EOF、trailers await、stream/future drop 和
  Store cleanup marker。报告位于
  `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-http-response-adapter-report.md`。
  该 checkpoint 仅关闭 response body 子批次，Step 3 仍有 filesystem、
  record-stream、stream-writer、Result 等 Rust gate 待迁移。

  **实施 checkpoint (2026-08-31 remaining filesystem):**
  `test_rust_wasi_filesystem_get_flags.sh`、
  `test_rust_wasi_filesystem_get_type.sh`、
  `test_rust_wasi_filesystem_sync.sh` 与
  `test_rust_wasi_filesystem_sync_data.sh` 已将 generated/cancel 组件的
  parse、embed、new、validate 全部切换到 current-only `bin/do-toolchain`，
  使用 `component-async` profile。4/4 脚本在根目录和无关 `/tmp` cwd 通过，
  保留 filesystem result/error/cancel、descriptor drop 和 Store cleanup
  marker。报告位于
  `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-filesystem-remaining-adapter-report.md`。
  该 checkpoint 仅关闭剩余 filesystem 子批次，Step 3 仍有 Result、
  record-stream、stream-writer 等 Rust gate 待迁移。

  **实施 checkpoint (2026-08-31 Result):**
  `test_rust_owned_error_result_shape.sh`、
  `test_rust_resource_cancellation_shape.sh`、
  `test_rust_scalar_result.sh` 与
  `test_rust_scalar_result_budget_adapter.sh` 已将 generated/cancel/hand-written
  组件的 parse、embed、new、validate 全部切换到 current-only
  `bin/do-toolchain`，统一使用 `component-async` profile。4/4 脚本在根目录和
  无关 `/tmp` cwd 通过，保留 Result payload、GC/linear cancellation
  equivalence、budget/scheduler 和 cleanup marker。报告位于
  `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-result-adapter-report.md`。
  该 checkpoint 仅关闭 Result 子批次，Step 3 仍有 record-stream、
  stream-writer 等 Rust gate 待迁移。

  **实施 checkpoint (2026-08-31 record-stream):**
  基础、resource、多 resource、multiple-nested 以及 nested 二至六层共 10
  个 record-stream Rust gate 已统一使用 current-only `bin/do-toolchain`，
  将 parse/embed/new/validate 映射为 typed operations 和
  `component-async` profile。10/10 脚本在根目录和无关 `/tmp` cwd 通过，
  保留 pending/ready/error、entries、EOF、resource/future/stream drop 和
  `table-empty=true` marker。报告位于
  `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-record-stream-adapter-report.md`。
  该 checkpoint 仅关闭 record-stream 子批次，Step 3 仍有 stream-writer 等
  Rust gate 待迁移。

  **实施 checkpoint (2026-08-31 stream-writer):** 17 个 stream-writer Rust
  gate 已统一使用 current-only `bin/do-toolchain`，Core parse、Component
  assembly/new/validate 均通过 typed operations；根目录和无关 `/tmp` cwd
  各 17/17 通过。`bash -n`、legacy direct-tool scan 和 scoped
  `git diff --check` 均通过。保留 guest producer、descriptor/helper/多跳
  forwarding、parameterized count/value、pending/ready/error/cancel、预算与
  scheduler admission/rejection、writer/reader drop 和 exactly-once cleanup
  marker。报告位于
  `.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step3-stream-writer-adapter-report.md`。
  该 checkpoint 闭合 Task 8 Step 3；Task 4 map runtime 仍独立受通用
  map/pair-list ABI lowering 阻断。

- [ ] **Step 4: 保留或删除 Shell 启动入口。**

  将 `run_tests.sh` 缩减为调用 `cd src && zig build test` 的薄入口；当 CI 和文档均改用 Zig 入口后删除重复 Shell 逻辑。不得修改 `.deps/wit-bindgen`。

- [ ] **Step 5: 每批运行对等性验证。**

  Run: `bash <old-gate>`（迁移前保存的基线）与 `cd src && zig build test --summary all`。

  Expected: 两者对同一 fixture 的退出码、错误分类、WAT/WIT marker、Rust lifecycle marker 一致；差异必须记录为明确的契约修订。

### Task 9: 完成 active 文档、门禁和发布回归

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `CHANGELOG.md`
- Create: `src/build/test/check_toolchain_adapter.sh`
- Test: full repository gates

**Interfaces:**
- Consumes: Tasks 1–8 的 lock、probe JSON、map lifecycle evidence、Zig harness 报告和 Rust 48.0.1 结果。
- Produces: active 文档与实现一致、升级可回滚、current-only 和 map lifecycle 门禁闭环。

- [ ] **Step 1: 添加集中式 active gate。**

  `check_toolchain_adapter.sh` 只检查 lock identity、adapter probe、active raw command scan 和旧版 executable-path 引用；历史 `doc/` 与 dated plan 不参与 raw scan。

- [ ] **Step 2: 同步 active 文档。**

  记录 map 是否支持、pair-list 只是 ABI 表示、operation lifetime、Zig test 入口、Rust runner 保留原因和 current-only 版本；删除 active route 对旧版本的要求，不改历史证据。

- [ ] **Step 3: 运行完整验证。**

  Run: `cd src && zig build test --summary all`; `./src/build/test/run_tests.sh`; `bash src/build/test/check_toolchain_adapter.sh`; `git diff --check`; `cargo test --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml`。

  Expected: 编译器回归、map focused tests、Component assembly、Rust/Wasmtime lifecycle、current-only adapter 和 Shell-to-Zig 对等性全部通过；任何失败保留原始输出并按 P0/P1/P2/P3 分级。

- [ ] **Step 4: 形成回滚点。**

  回滚只恢复 `toolchain/toolchain.lock.json`、adapter 和 harness 入口；不得通过恢复旧 compiler semantic code 来掩盖工具链或 runtime failure。

- [ ] **Step 5: 交付前检查工作区。**

  Run: `git status --short`, `git diff --stat`, `git diff --check`。

  Expected: 只包含本计划允许的规格、adapter、map、harness、active gate 和文档变更；现有未相关 dirty 改动保持原状。
