# Current Toolchain Compatibility Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让项目在当前现场的 Zig 0.17.0、wasm-tools 1.261.0、Wasmtime 50.0.0 和 Rust/Cargo 1.99.1 下可构建、可验证，并将工具检查从精确版本/hash 锁定改为能力兼容检查。

**Architecture:** 保留 Zig harness 和现有 WAT/WIT/Component 验证边界，把工具链配置改为描述当前能力而不是固定安装路径和 SHA256。先修复 Zig 0.17 的 Build API 兼容性，再用当前 wasm-tools/Wasmtime/Rust 跑静态、组装和真实 host gate; 历史设计文档保留其当时的版本证据，不做机械重写。

**Tech Stack:** Zig 0.17.0, wasm-tools 1.261.0, Wasmtime 50.0.0, Rust/Cargo 1.99.1, Bash, Node.js, WAT/WIT, existing Zig test harness.

**Spec:** 用户确认的方案 1: 使用当前工具版本, 不强制锁定精确版本/hash, 但保留能力探测和真实 smoke 验证。

## Global Constraints

- 不覆盖或回退工作区已有 enum 变更: `doc/spec_rules.md`, `doc/syntax/enum.md`, `src/build/codegen_collect_util.zig`, `src/build/test/ok/100_value_enum_nullable.do`, `src/build/test/err/411_*`。
- 不删除 Rust host runner; 它仍用于当前 Component/WASI 真实运行验证。
- 不用兼容旧版 Zig 的 fallback 分支掩盖新版本错误; Build API 迁移必须保持原有 install/run/test 语义。
- 不机械修改历史 `doc/superpowers/specs/` 和 `doc/superpowers/plans/` 的旧版本记录。
- 工具版本漂移必须在诊断或验证输出中可见; 缺少必需能力时早失败并报告工具和能力。

## Review Focus

- Zig install prefix 语义是否仍把 `do` 和 `do-toolchain` 安装到仓库 `bin/`, 并由 harness 使用相同路径; test in Task 1.
- wasm-tools 子命令名称和 Component assemble/validate 结果是否仍兼容; test in Task 2.
- Wasmtime 50 的 core GC 与 Component CLI 能力是否仍覆盖现有 gate; test in Task 3.
- Rust 1.99/Cargo 1.99 是否能在 `rust-host-runner` 的 locked dependency graph 下构建; test in Task 3.
- 旧锁文件路径、SHA 或版本字段是否仍被 harness 当作强制合同; test in Task 2 and Task 4.

### Task 1: Migrate the Zig build entrypoint to Zig 0.17

**Files:**
- Modify: `src/build.zig:3-6`.
- Test: `src/build/test/run_tests.sh` and the installed binary path used by the harness.

**Interfaces:**
- Consumes: Zig 0.17 `std.Build` API.
- Produces: `bin/do`, `bin/do-toolchain`, and the existing `test` step with unchanged names and environment wiring.

- [ ] **Step 1: Write a focused build smoke check** that verifies `zig build -Doptimize=Debug` exits successfully, installs both binaries under the repository `bin/`, and can execute `do --help`.
- [ ] **Step 2: Run the smoke check and verify the expected current failure** at `resolveInstallPrefix` before changing production code.
- [ ] **Step 3: Replace the obsolete Zig 0.16 install-prefix call with the Zig 0.17 install directory configuration while preserving `b.getInstallPath(.bin, ...)` behavior.
- [ ] **Step 4: Run `zig fmt --check src/build.zig` and the focused build smoke; verify both binaries exist and execute.

### Task 2: Replace exact tool lock enforcement with capability discovery

**Files:**
- Modify: `toolchain/toolchain.lock.json`.
- Modify: `src/build/test/test_harness.zig` and the toolchain adapter/validation code identified by the existing lock consumers.
- Modify: `src/build/test/check_toolchain_adapter_test.sh` and related toolchain tests as needed.
- Test: tool version/capability preflight and component assembly smoke.

**Interfaces:**
- Consumes: PATH-resolved `zig`, `wasm-tools`, `wasmtime`, `rustc`, and `cargo`.
- Produces: a schema-compatible toolchain capability record with observed versions, executable paths, and required command/feature checks; no exact SHA equality requirement.

- [ ] **Step 1: Add failing tests** for a valid current tool set with changed versions/paths and for a missing required capability; assert diagnostics identify the tool and missing capability.
- [ ] **Step 2: Run those tests and confirm the current exact-lock implementation rejects the changed versions.
- [ ] **Step 3: Implement capability-based validation: resolve executables from environment/PATH, probe required commands, record observed versions, and reserve exact hashes for optional evidence rather than admission.
- [ ] **Step 4: Run the adapter tests and a real `wasm-tools component embed/new/validate` smoke on an existing fixture; verify current 1.261 behavior.

### Task 3: Migrate runtime and Cargo gates to current tools

**Files:**
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` or runner source only if Wasmtime 50 API/feature changes require it.
- Modify: `examples/p3-runtime/*.sh`, `examples/wit-bindgen-do/*.sh`, and GC gate scripts only where current command/API behavior requires a change.
- Modify: `toolchain/toolchain.lock.json` observed Rust/Cargo/Wasmtime records.
- Test: focused Rust host runner gates, core Wasmtime gates, and generated async/component gates.

**Interfaces:**
- Consumes: Task 2 capability record and current Wasmtime/wasm-tools executables.
- Produces: unchanged host runner observable contracts: result values, pending/ready/cancel behavior, resource/drop counters, and empty resource tables.

- [ ] **Step 1: Run the smallest existing Rust/Wasmtime gate with Rust 1.99 and Wasmtime 50, capturing the first compile, link, WIT, or runtime failure without changing expectations.
- [ ] **Step 2: For each failure, add or update the narrowest regression assertion before changing runner code.
- [ ] **Step 3: Apply only required API/feature/CLI migrations; keep the observable ABI and cleanup counts unchanged.
- [ ] **Step 4: Run focused resource, async, stream/future, and GC core gates; record pass counts and remaining unsupported boundaries.

### Task 4: Update current-tool documentation and complete verification

**Files:**
- Modify: `README.md` and current toolchain documentation that claims exact active versions.
- Modify: current toolchain capability schema/tests if Task 2 changes its fields.
- Do not modify: historical design/planning evidence whose versions describe past runs.

**Interfaces:**
- Consumes: observed results from Tasks 1-3.
- Produces: documentation that distinguishes current environment capability from historical pinned evidence.

- [ ] **Step 1: Add a documentation test/check for the current tool preflight command and its failure format.
- [ ] **Step 2: Run the full `./src/build/test/run_tests.sh` with the current toolchain; record exact failures if the environment or external tools still block it.
- [ ] **Step 3: Run `git diff --check`, Zig formatting checks, focused component/runtime gates, and inspect generated artifacts for unintended ABI drift.
- [ ] **Step 4: Summarize verified, blocked, and unverified toolchain paths without claiming full compatibility unless the full gate passes.
