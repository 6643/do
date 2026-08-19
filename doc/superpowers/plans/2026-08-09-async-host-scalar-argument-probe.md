# Async Host Scalar-Argument Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Add one independent, probe-only Component/Rust/Wasmtime gate proving that a colorless Do helper can pass one \`u32\` argument through an asynchronous host call and root-owned continuation frame.

**Architecture:** Keep the probe outside the Do compiler promotion path. A checked-in WIT file defines the private \`do:async-call-arg-probe@0.1.0\` world, a hand-authored Core WAT records the measured async import and frame offsets, and one Bash gate assembles/validates the Component and drives a Rust/Wasmtime host oracle. The probe accepts only the fixed \`helper(7)\` source model; no registry descriptor, semantic admission, codegen target, or public ownership syntax is added.

**Tech Stack:** Zig 0.16.0, the Do compiler for regression-only checks, WIT/Core WAT, \`wasm-tools\` 1.255.0 plus the pinned legacy 1.254.0 async assembly route, Rust 1.97.1, Wasmtime 47.0.2, Cargo \`--locked\`, Bash, and the existing \`src/build/test/run_tests.sh\` harness.

## Global Constraints

- Preserve \`main\` behavior and leave \`src/build/p3_async_registry.json\` byte-for-byte unchanged.
- Do not modify \`sema_imports.zig\`, \`codegen_component_async_call.zig\`, any v1/v2 dispatcher, or default async diagnostics.
- Keep the exact source shape from \`doc/superpowers/specs/2026-08-09-async-host-scalar-argument-probe-design.md\): \`work(u32) -> nil\`, \`helper(value u32)\`, and \`@async(helper(7))\` followed by one \`@await\`.
- Use private package \`do:async-call-arg-probe@0.1.0\`, host instance \`do:async-call-arg-probe/host@0.1.0\`, operation \`work\`, and world \`probe\`.
- Pin \`wasm-tools 1.255.0 (76e20611d 2026-07-30)\` with SHA-256 \`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013\`.
- Pin legacy \`wasm-tools 1.254.0 (bb58fdf91 2026-07-20)\` with SHA-256 \`cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6\` for async assembly where required.
- Pin Rust \`1.97.1\` and Wasmtime \`47.0.2\`; use the existing component-model-async feature set.
- Cancellation releases live guest/Component state exactly once and never rolls back an external host effect already issued.
- A failed pinned probe is a no-go. Preserve exact stderr in \`doc/pending_blocked.md\` and do not add a compatibility fallback.

---

### Task 1: Freeze the baseline and add the private WIT source

**Files:**
- Verify: \`doc/superpowers/specs/2026-08-09-async-host-scalar-argument-probe-design.md\`
- Create: \`examples/p3-runtime/wit/async-call-arg-probe.wit\`
- Verify: \`doc/start_here.md\`, \`doc/roadmap_status.md\`, \`doc/pending_blocked.md\`

**Interfaces:**
- Consumes: clean \`main\), pinned tools, and the approved design.
- Produces: one pinned WIT source with package/world/member identity; no compiler descriptor.

- [ ] **Step 1: Verify checkout and tools.**

Run:

~~~bash
git status --short --branch
git log -1 --oneline --decorate
git rev-parse main origin/main
zig version
wasm-tools --version
rustc --version
wasmtime --version
~~~

Expected: clean \`main\), Zig \`0.16.0\`, current \`wasm-tools 1.255.0\`, Rust \`1.97.1\`, and Wasmtime \`47.0.2\`. Resolve the legacy 1.254.0 executable explicitly when the assembly gate runs.

- [ ] **Step 2: Add the exact WIT package.**

Create \`examples/p3-runtime/wit/async-call-arg-probe.wit\`:

~~~wit
package do:async-call-arg-probe@0.1.0;

interface host {
  work: async func(value: u32);
}

world probe {
  import host;
  export run: async func();
}
~~~

- [ ] **Step 3: Validate and record the WIT hash.**

Run:

~~~bash
wasm-tools component wit examples/p3-runtime/wit/async-call-arg-probe.wit
sha256sum examples/p3-runtime/wit/async-call-arg-probe.wit
git diff --check
~~~

Expected: package \`do:async-call-arg-probe@0.1.0\`, \`host.work: async func(value: u32)\`, and \`world probe\` with \`run\` export. Commit only this source:

~~~bash
git add examples/p3-runtime/wit/async-call-arg-probe.wit
git commit -m "test: add async host scalar argument WIT probe"
~~~

### Task 2: Write the measured canonical Core WAT

**Files:**
- Create: \`examples/p3-runtime/async-call-arg-probe-canonical.wat\`
- Verify: \`examples/p3-runtime/async-call-scalar-argument-probe.wat\`
- Verify: \`examples/p3-runtime/async-call-component-local-frame-probe.wat\`

**Interfaces:**
- Consumes: WIT custom-section output from Task 1 and the existing root-owned local-frame patterns.
- Produces: a standalone Core module exporting \`[async-lift]run\`, \`[callback][async-lift]run\`, \`cabi_realloc\`, and \`_initialize\`, with no helper task export.

- [ ] **Step 1: Generate and compare both pinned custom sections.**

Run:

~~~bash
WASM_TOOLS=/path/to/wasm-tools-1.255.0 wasm-tools component embed examples/p3-runtime/wit/async-call-arg-probe.wit --world probe --dummy-names legacy --async-callback -t > /tmp/async-call-arg-probe-1.255-dummy.wat
WASM_TOOLS=/path/to/wasm-tools-1.254.0 wasm-tools component embed examples/p3-runtime/wit/async-call-arg-probe.wit --world probe --dummy-names legacy --async-callback -t > /tmp/async-call-arg-probe-1.254-dummy.wat
~~~

The package/world/member identity must agree. If flat parameter/result words differ, record both outputs and stop; do not choose one by guesswork.

- [ ] **Step 2: Implement the fixed root-owned frame.**

The WAT must contain measured types/imports for \`[async-lower]work\`, root task cancel/return, waitable-set lifecycle, context get/set, and subtask cancel/drop. Record explicit comments for frame size, alignment, waitable handle, active subtask handle, helper state, and one \`u32\` argument slot. Store literal \`7\` before the host call and load the same slot after the root callback.

Required markers:

~~~text
[guest-async-arg-store]
[guest-async-host-arg]
[guest-async-arg-load]
[guest-async-parent-resume]
[guest-async-child-drop]
[guest-async-waitable-drop]
[guest-async-context-clear]
[guest-async-frame-free]
~~~

The WAT must contain no \`[task-return]helper\`, no resource-drop import, and no list/stream/resource payload storage. Ready and terminal completion must call root \`task.return\`; cancellation must drop active state and call root \`task.cancel\`.

- [ ] **Step 3: Parse and inspect the Core module.**

Run:

~~~bash
wasm-tools parse examples/p3-runtime/async-call-arg-probe-canonical.wat -o /tmp/async-call-arg-probe.core.wasm
rg -n "guest-async-(arg-store|host-arg|arg-load|parent-resume|child-drop|waitable-drop|context-clear|frame-free)" examples/p3-runtime/async-call-arg-probe-canonical.wat
! rg -n "\[task-return\]helper|\[resource-drop\]|stream-|list-" examples/p3-runtime/async-call-arg-probe-canonical.wat
~~~

Expected: parse succeeds, every required marker appears, and forbidden markers are absent. Commit:

~~~bash
git add examples/p3-runtime/async-call-arg-probe-canonical.wat
git commit -m "test: add async host scalar argument canonical WAT"
~~~

### Task 3: Add the pinned Component assembly gate

**Files:**
- Create: \`examples/p3-runtime/test_async_call_arg_probe.sh\`
- Verify: \`examples/p3-runtime/wit/async-call-arg-probe.wit\`
- Verify: \`examples/p3-runtime/async-call-arg-probe-canonical.wat\`

**Interfaces:**
- Consumes: the WIT and Core WAT from Tasks 1-2.
- Produces: a temporary Component artifact for the Rust oracle and an auditable result for both pinned toolchains.

- [ ] **Step 1: Add version/hash guards.**

The script accepts \`WASM_TOOLS\` and \`WASM_TOOLS_EXPECT_VERSION\`, defaulting to \`1.255.0\`. It must use this exact selector table:

~~~bash
case "$WASM_TOOLS_EXPECT_VERSION" in
  1.255.0) expected_version='wasm-tools 1.255.0 (76e20611d 2026-07-30)'; expected_sha256='6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013' ;;
  1.254.0) expected_version='wasm-tools 1.254.0 (bb58fdf91 2026-07-20)'; expected_sha256='cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6' ;;
  *) printf 'unsupported probe version selector: %s\n' "$WASM_TOOLS_EXPECT_VERSION" >&2; exit 2 ;;
esac
~~~

Resolve PATH names with \`command -v\`, require explicit paths to be executable, and compare both \`--version\` and \`sha256sum\` before assembly.

- [ ] **Step 2: Assemble and validate the Component.**

For each pinned binary, use a \`mktemp -d\` and cleanup trap, then run:

~~~bash
wasm-tools parse "$core_wat" -o "$tmp_dir/core.wasm"
wasm-tools component embed "$wit" --world probe --dummy-names legacy --async-callback -t > "$tmp_dir/dummy.wat"
custom_line=$(grep '^  (@custom "component-type"' "$tmp_dir/dummy.wat" || true)
test -n "$custom_line"
wasm-tools strip -a "$tmp_dir/core.wasm" -o "$tmp_dir/stripped.wasm"
wasm-tools print "$tmp_dir/stripped.wasm" > "$tmp_dir/stripped.wat"
sed '$d' "$tmp_dir/stripped.wat" > "$tmp_dir/custom.wat"
printf '%s\n' "$custom_line" ')' >> "$tmp_dir/custom.wat"
wasm-tools parse "$tmp_dir/custom.wat" -o "$tmp_dir/custom.wasm"
wasm-tools component new --skip-validation "$tmp_dir/custom.wasm" -o "$tmp_dir/component.wasm"
wasm-tools validate --features cm-async,cm-more-async-builtins "$tmp_dir/component.wasm"
~~~

Print the selected version/hash, WIT hash, frame size/argument offset, and Component path. A route-specific failure is a no-go.

- [ ] **Step 3: Add negative boundary assertions.**

Before \`component new\`, assert no \`[task-return]helper\`, resource-drop, list, stream, or payload marker exists. Mutate temporary WIT copies to \`u64\` and two host parameters and require the custom-section/Core-WAT pairing to fail during Component assembly. Print the source-level no-go set (non-literal argument, missing/extra call argument, helper payload, second await, multiple live children, resource/list/stream/borrowed payload, independent helper task, legacy \`async\`) as explicit boundary rows; these become compiler negative fixtures only in a later promotion plan.

- [ ] **Step 4: Run and commit the gate.**

~~~bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_async_call_arg_probe.sh
WASM_TOOLS_EXPECT_VERSION=1.254.0 WASM_TOOLS=/path/to/wasm-tools-1.254.0 bash examples/p3-runtime/test_async_call_arg_probe.sh
git add examples/p3-runtime/test_async_call_arg_probe.sh
git commit -m "test: add async host scalar argument Component gate"
~~~

### Task 4: Add the Rust/Wasmtime argument oracle

**Files:**
- Create: \`examples/p3-runtime/rust-host-runner/src/bin/async_call_arg_probe.rs\`
- Modify: \`examples/p3-runtime/rust-host-runner/Cargo.toml\` with one \`[[bin]]\` entry
- Verify: \`examples/p3-runtime/rust-host-runner/Cargo.lock\`

**Interfaces:**
- Consumes: the Component path from Task 3 and mode \`ready\`, \`pending\`, or \`cancel\`.
- Produces: deterministic observations of host argument value, wake/completion/drop counters, cancellation, and \`ResourceTable\` emptiness.

- [ ] **Step 1: Register the runner and define stats.**

Add:

~~~toml
[[bin]]
name = "do-p3-async-call-arg-probe-host-runner"
path = "src/bin/async_call_arg_probe.rs"
~~~

Parse exactly \`<component.wasm> <ready|pending|cancel>\`. Track atomics for \`host_calls\`, \`last_argument\`, \`argument_mismatches\`, \`polls\`, \`external_wakes\`, \`completions\`, \`future_drops\`, \`pending_future_drops\`, and \`guest_completed\`.

- [ ] **Step 2: Implement the controlled host operation.**

Link instance \`do:async-call-arg-probe/host@0.1.0\` and function \`work(value: u32)\`. The concurrent closure increments calls, stores the received value, increments mismatches unless it equals \`7\`, and returns a controlled Future. \`ready\` completes immediately, \`pending\` arms one external wake, and \`cancel\` remains pending so the root call can be cancelled after one observed host call.

- [ ] **Step 3: Drive Wasmtime and assert all modes.**

Use the existing component async configuration, instantiate a fresh Store with an empty \`ResourceTable\`, call typed export \`run: () -> ()\`, and use \`futures::future::select\` for cancellation after \`host_calls == 1\`.

Required exact assertions:

~~~text
ready:   calls=1 argument=7 completions=1 future-drops=1 pending-drops=0 guest-completed=true table-empty=true
pending: calls=1 argument=7 external-wakes=1 completions=1 future-drops=1 pending-drops=0 guest-completed=true table-empty=true
cancel:  calls=1 argument=7 completions=0 future-drops=1 pending-drops=1 guest-completed=false table-empty=true
~~~

Allow \`polls >= 2\` for pending, but do not weaken exact call, argument, completion, drop, or table assertions. Print one stable \`mode=...\` line per mode.

- [ ] **Step 4: Check and commit the runner.**

~~~bash
cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml --bin do-p3-async-call-arg-probe-host-runner
cargo fmt --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml -- --check
git add examples/p3-runtime/rust-host-runner/Cargo.toml examples/p3-runtime/rust-host-runner/src/bin/async_call_arg_probe.rs
git commit -m "test: add async host scalar argument Wasmtime oracle"
~~~

### Task 5: Close out the probe without claiming compiler promotion

**Files:**
- Modify: \`doc/roadmap_status.md\`
- Modify: \`doc/start_here.md\`
- Modify: \`doc/pending_blocked.md\` only if the probe is red or the boundary changes
- Modify: \`CHANGELOG.md\`
- Verify unchanged: \`src/build/p3_async_registry.json\`, \`src/build/sema_imports.zig\`, \`src/build/codegen_component_async_call.zig\`

**Interfaces:**
- Consumes: green or no-go output from Tasks 1-4.
- Produces: truthful status saying scalar host-argument ABI is probe-green (or blocked), while general async-call lowering remains pending.

- [ ] **Step 1: Run the complete verification matrix.**

Run:

~~~bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_async_call_arg_probe.sh
cd src && zig test main.zig
cd .. && ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
~~~

The Component gate must drive the Rust runner for \`ready\`, \`pending\`, and \`cancel\`, or invoke the runner explicitly after producing its temporary Component. Record the exact command and all three output rows.

- [ ] **Step 2: Check isolation.**

Run:

~~~bash
git diff --name-only origin/main..HEAD -- src/build/p3_async_registry.json src/build/sema_imports.zig src/build/codegen_component_async_call.zig
git diff --check
~~~

Expected: no compiler/registry output and no public ownership syntax in the diff.

- [ ] **Step 3: Update status only after fresh green output.**

Record the WIT hash, both toolchain versions/hashes, measured frame size and argument offset, three mode observations, and empty \`ResourceTable\` in \`doc/roadmap_status.md\` and \`doc/start_here.md\`. Keep general async-call promotion, arbitrary producer expressions, payload/resource/stream futures, borrowed async values, public ownership syntax, general filesystem async, and external HTTP explicitly pending. Add one concise \`CHANGELOG.md\` entry.

If any gate is red, do not mark the probe green. Append exact command and stderr to the G6.2/async boundary row in \`doc/pending_blocked.md\`, leave compiler and registry untouched, and stop at the failed gate.

- [ ] **Step 4: Final history/worktree check and closeout commit.**

~~~bash
git status --short --branch
git diff --check
git log --oneline --decorate -8
git add doc/roadmap_status.md doc/start_here.md CHANGELOG.md doc/pending_blocked.md
git commit -m "docs: close async host scalar argument probe"
~~~

## Completion Boundary

The plan is complete when both pinned toolchain routes assemble and validate the independent probe, Rust/Wasmtime observes argument \`7\` with exact cleanup in all three modes, and the full compiler regression remains green without widening compiler admission. A later compiler promotion plan is required to add a private descriptor, exact semantic admission, an isolated emitter, compiler fixtures, and a generated Component gate.
