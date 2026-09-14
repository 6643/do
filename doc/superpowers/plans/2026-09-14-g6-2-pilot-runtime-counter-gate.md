# G6.2 Pilot Runtime Counter Gate 实施计划

> 本计划只覆盖 test-only counter gate。canonical route、默认 dispatch 和公开语言能力不变。

## 文件边界

- Create: `src/build/codegen_component_producer_runtime_counters.zig` — 固定 direct WAT anchor instrumentation。
- Create: `src/build/codegen_component_producer_runtime_counters_test.zig` — 正向、anchor drift、重复 anchor、canonical 不变测试。
- Modify: `src/build/codegen_component_owned_record_stream_producer.zig` — 暴露 private test-only instrumentation entry，复用既有 pilot admission。
- Modify: `src/main.zig` — 只导入 counter unit tests。
- Create: `examples/p3-runtime/wit/g6-2-owned-record-producer-counters.wit` — 独立 test-only world。
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_owned_record_producer_counters_abi.rs` — Component counter runner。
- Create: `examples/p3-runtime/test_rust_g6_2_owned_record_producer_counters.sh` — current-toolchain assembly、十模式 gate 和 cache isolation。
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` — 仅在确有新 binary 配置需要时修改。
- Modify: G6.2 plan/report/status docs — 记录 observed tuple、失败证据和 residual closure。

## Task 1: instrumentation RED/green

1. 先写测试，要求 canonical WAT 输入保持 byte-identical，固定 direct anchors 缺失或重复时返回 named error，instrumented output 必须包含 test-only marker、四个 counter globals、唯一 counter export。
2. 运行 focused filter，确认未实现时为 RED。
3. 实现 allocation-free anchor validation 与 WAT instrumentation；不扫描任意 WAT，不改默认 emitter。
4. 运行 focused counter tests、`zig fmt` 和 `git diff --check`。

验收: counter helper 只接受 direct canonical artifact；任何静默 fallback 都被测试拒绝。

## Task 2: private WIT assembly probe

1. 添加 counter world，复用原 types/source/sink/produce，增加 `runtime-counters: func() -> tuple<u32,u32,u32,u32>`。
2. 新增脚本生成 canonical pilot，再生成 instrumented WAT，分别 parse-core、embed-component、new-component、validate-component。
3. 脚本检查 canonical WAT/WIT hash 不变，instrumented artifact 带 test-only marker，counter world hash 固定并记录。

验收: current `wasm-tools 1.258.0` 能组装并验证 test-only Component；若失败，保留失败日志并关闭该实现路径，不伪造通过。

## Task 3: Rust/Wasmtime observed counters

1. runner 安装与原 direct route 相同的 source/sink/type host bindings。
2. 实例化 test-only Component，先执行 `produce`，再读取 `runtime-counters`。
3. 对十个 mode 断言 result、既有 lifecycle counters、table empty 和 component-returned counter tuple。
4. output 明确打印 `counter-source=component` 和 observed values；不得打印只由 expected cardinality 推导的 list/frame 数作为 observed。

验收: 十模式全部 exact pass；任何 export 缺失或 tuple 漂移 fail closed。

## Task 4: rollback and repository gates

1. 保留 canonical direct gate、default route byte parity 和既有 rollback copy；确认 instrumentation 不被默认 dispatch 调用。
2. 运行 focused unit/assembly/runner gates、full `zig test main.zig`、ReleaseSmall、`run_tests.sh`、release smoke。
3. 运行 ARC inventory/post-cutover closure，确认没有新的 normal-route ARC marker。
4. 更新 Task 6 Step 3、plan/spec、`start_here.md`、`master_plan.md`、`pending_blocked.md`、`CHANGELOG.md`。

验收: 只有 component counter tuple 和全套既有 gates 均通过，才能将 G6.2 pilot 从 `complete-with-residuals` 改为 `complete`；否则保留 residual 与原始失败日志。

## 标准命令

```bash
cd src
TMPDIR="$PWD/../.tmp/do-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
zig test main.zig --test-filter "producer runtime counter"

cd ..
bash examples/p3-runtime/test_rust_g6_2_owned_record_producer_counters.sh
./src/build/test/run_tests.sh
```

每个失败命令必须保留输出，并区分源码、工具链和环境原因。
