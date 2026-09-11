# G6.2 Canonical-to-Frame Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 12 个现有 G6.2 producer template 建立可机器验证的 canonical-to-frame facts 和只读 decomposition/parity probe，不改变现有产物。

**Architecture:** 新增独立 test-only probe 模块，消费静态 `TemplateFact` 表和现有 template bytes。模块只做 facts 校验、marker/anchor 定位和 canonical prefix/suffix parity 检查；现有 route emitter、template、contract 和 compiler dispatch 保持不变。

**Tech Stack:** Zig std library、现有 `codegen_component_producer_runtime_audit.zig` validation primitives、embedded WAT templates、仓库 Zig test/build harness。

**Spec:** `doc/superpowers/specs/2026-09-12-g6-2-canonical-frame-probe-design.md`

## Global Constraints

- 不改 WAT/WIT bytes、descriptor/WIT hash、diagnostic、runtime counter 或公开能力语义。
- 不删除、重写或替换任何 producer template，不创建 production shared emitter。
- 不新增 `own<T>`、`borrow<T>`、`ref<T>`、generic producer admission 或 arbitrary producer expression。
- probe 只读取显式 facts 和 immutable template bytes；不读 lexer/registry，不生成 WAT。
- `0` 是合法 offset/handle；缺失必须由空/缺失 entry 表示。
- 运行验证使用仓库本地 Zig cache：`TMPDIR="$PWD/.tmp/do-tmp"`、`ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/zig-cache"`、`ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/zig-gcache"`。

## Files

- Create: `src/build/codegen_component_producer_mapping_probe.zig` — facts、marker parser、decomposition/parity API。
- Create: `src/build/codegen_component_producer_mapping_probe_test.zig` — 12 template positive coverage and negative gates。
- Modify: `src/main.zig: test-root imports` — import the new test root only。
- Create: `doc/superpowers/specs/2026-09-12-g6-2-canonical-frame-probe-design.md` — approved design。
- Create: `doc/superpowers/plans/2026-09-12-g6-2-canonical-frame-probe.md` — this plan。

### Task 1: Define probe facts and validation API

**Files:**
- Create: `src/build/codegen_component_producer_mapping_probe.zig`
- Test: `src/build/codegen_component_producer_mapping_probe_test.zig`

**Interfaces:**
- Consumes: `RuntimeField`, `CanonicalBinding`, `TemplateAuditSpec` concepts from `codegen_component_producer_runtime_audit.zig`。
- Produces: `FrameFact`, `OwnershipEncoding`, `OwnershipFact`, `BindingFact`, `LifecycleFact`, `TemplateFact`, `TemplateObservation`, `ProbeError`, `validate_facts`。

- [ ] **Step 1: Write failing fact validation tests**

  Add tests for one valid scalar route and failures for empty route, field overlap, binding overlap, and invalid ownership encoding.

- [ ] **Step 2: Run focused test and verify failure**

  Run:
  ```bash
  cd src && TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer canonical frame probe"
  ```
  Expected: FAIL because the new probe types/functions are not defined.

- [ ] **Step 3: Implement facts and fail-closed validator**

  Implement borrowed slices, explicit ownership encoding, interval checks, and `validate_facts` without allocation or WAT emission. Reject zero-sized frame, out-of-range fields/bindings, overlaps, empty lifecycle anchors, and batch alias ranges.

- [ ] **Step 4: Run focused test and verify pass**

  Re-run the focused command; expected: all Task 1 fact tests PASS.

### Task 2: Add the 12 checked-in template fact entries

**Files:**
- Modify: `src/build/codegen_component_producer_mapping_probe.zig`
- Test: `src/build/codegen_component_producer_mapping_probe_test.zig`

**Interfaces:**
- Consumes: `TemplateFact` and `validate_facts` from Task 1。
- Produces: `pub const checked_in_template_facts: []const TemplateFact` with exactly 12 entries and `fact_for_route` lookup。

- [ ] **Step 1: Write failing coverage test**

  Assert exactly 12 unique template names, `frame_size == 128` per entry, non-empty frame/binding/lifecycle facts, and route-specific marker sets (record, C-min, scalar, batched).

- [ ] **Step 2: Run test to capture the missing table**

  Run the focused command; expected: FAIL on missing table/lookup.

- [ ] **Step 3: Implement the table from checked-in template comments and route constants**

  Encode the observed frame slots (0/4/8/12/16/20/32/36/40 plus payload slots), scalar/mask/batched ownership values, canonical payload offsets, and each route's actual marker names. Keep all slices backed by module constants.

- [ ] **Step 4: Run the 12-entry coverage test**

  Expected: PASS with no duplicate route or template identity and all entries passing `validate_facts`.

### Task 3: Implement marker extraction and template decomposition

**Files:**
- Modify: `src/build/codegen_component_producer_mapping_probe.zig`
- Test: `src/build/codegen_component_producer_mapping_probe_test.zig`

**Interfaces:**
- Consumes: `TemplateFact` entries and immutable template bytes。
- Produces: `decompose_template(template, fact) ProbeError!TemplateObservation` and `marker_value(template, marker) ?[]const u8`。

- [ ] **Step 1: Add failing positive/negative decomposition tests**

  For all 12 embedded templates, require every fact marker and lifecycle anchor; mutate an in-memory copy to remove a marker and reorder two anchors, expecting `MissingMarker` and `LifecycleOrder`.

- [ ] **Step 2: Run focused test and verify failure**

  Expected: FAIL because decomposition functions are not implemented.

- [ ] **Step 3: Implement read-only marker/anchor scan**

  Scan existing `[producer-*]` comments and lifecycle function anchors without modifying bytes. Numeric markers must match their fact value; marker presence must remain route-specific. Return borrowed offsets/counts in `TemplateObservation`.

- [ ] **Step 4: Run all 12 decomposition tests**

  Expected: PASS; no template file changes.

### Task 4: Add canonical/generated prefix-suffix parity probe and negative gates

**Files:**
- Modify: `src/build/codegen_component_producer_mapping_probe.zig`
- Test: `src/build/codegen_component_producer_mapping_probe_test.zig`

**Interfaces:**
- Consumes: canonical template bytes and generated WAT bytes。
- Produces: `verify_canonical_segments(canonical, generated) ProbeError!ParityObservation`。

- [ ] **Step 1: Write failing parity tests**

  Verify a generated string with metadata inserted before the final `\n)` passes; mutate one prefix byte, one suffix byte, and add a second canonical segment, expecting `CanonicalParity` or `DuplicateCanonicalSegment`. Add batch pointer alias and cleanup-order negative fact fixtures.

- [ ] **Step 2: Run focused test and verify failure**

  Expected: FAIL until the parity and negative gates exist.

- [ ] **Step 3: Implement parity and negative checks**

  Split canonical bytes at its final module close, require generated prefix/suffix byte equality and exactly one canonical segment boundary, and reuse interval/order validators for alias and cleanup failures. Do not compare or rewrite metadata bytes.

- [ ] **Step 4: Run focused probe suite**

  Expected: all positive and negative tests PASS.

### Task 5: Wire test root, format, full verification, and closeout docs

**Files:**
- Modify: `src/main.zig: test-root imports`
- Modify: `doc/superpowers/specs/2026-09-12-g6-2-canonical-frame-probe-design.md` — record actual evidence。
- Modify: `doc/superpowers/plans/2026-09-12-g6-2-canonical-frame-probe.md` — mark completed units。

- [ ] **Step 1: Add test-root import and format**

  Add only the new test module import, then run `zig fmt` on changed Zig files.

- [ ] **Step 2: Run focused probe gate**

  ```bash
  cd src && TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer canonical frame probe"
  ```

- [ ] **Step 3: Run full gates**

  ```bash
  (cd src && TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig)
  (cd src && TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig build -Doptimize=ReleaseSmall)
  ./src/build/test/run_tests.sh
  git diff --check
  ```

- [ ] **Step 4: Record evidence and residual risk**

  Update the spec/plan with actual counts and keep shared emitter/state IR explicitly deferred. Do not update capability status as completed.

- [ ] **Step 5: Commit the D1 slice**

  ```bash
  git add src/main.zig src/build/codegen_component_producer_mapping_probe.zig src/build/codegen_component_producer_mapping_probe_test.zig doc/superpowers/specs/2026-09-12-g6-2-canonical-frame-probe-design.md doc/superpowers/plans/2026-09-12-g6-2-canonical-frame-probe.md
  git diff --cached --check
  git commit -m "Add G6.2 canonical frame probe"
  ```

## Self-review checklist

- Spec requirement coverage: facts (Tasks 1-2), decomposition (Task 3), parity and negatives (Task 4), verification/docs (Task 5)。
- No production emitter, route migration, public ownership syntax, or fallback was added。
- All interfaces used by later tasks are defined in earlier tasks with exact names。
- 未完成占位语句和模糊的 placeholder instructions absent from executable steps。
