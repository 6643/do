# G6.2.4 Private Future-Owned Compiler Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Promote the measured Future<Ticket> source shape to a private,
opt-in Component target that emits future<own<ticket>>, with verified
ready/pending/cancel cleanup and no public ownership syntax.

**Design:** docs/superpowers/specs/2026-08-07-future-owned-compiler-promotion-design.md

**Toolchain:** Zig 0.16.0, wasm-tools 1.255.0, Wasmtime 47.0.2, Rust
1.97.1, and the existing pinned legacy async assembler where the generated
async metadata requires it.

**Constraints:** Preserve all unrelated dirty changes. Do not add own<T>,
borrow<T>, ref<T>, generic owned-future lowering, owned streams, borrowed
async values, generic producer expressions, filesystem async, or D2 I/O.

---

## File Map

Create:

- src/build/codegen_component_future_owned_plan.zig — exact source and
  descriptor admission; owns the immutable lowering plan.
- src/build/codegen_component_future_owned.zig — private WAT/WIT emission from
  the plan.
- src/build/codegen_component_future_owned_plan_test.zig — analyzer positive
  and negative unit fixtures.
- src/build/codegen_component_future_owned_test.zig — emitter marker/layout
  unit tests.
- examples/p3-runtime/future-owned-component.do — compiler positive source.
- examples/p3-runtime/future-owned-component.wit — expected WIT snapshot.
- examples/p3-runtime/test_do_future_owned_component.sh — compile, sidecar,
  target-isolation, parse, and Component assembly gate.
- examples/p3-runtime/test_rust_future_owned_component.sh — Rust/Wasmtime
  ready/pending/cancel gate wrapper.
- src/build/test/compile_err/444_future_owned_component_unregistered.do and
  .expect — missing descriptor rejection.
- src/build/test/compile_err/445_future_owned_component_payload.do and
  .expect — non-resource future payload rejection.
- src/build/test/compile_err/446_future_owned_component_two_awaits.do and
  .expect — multiple-await rejection.

Modify:

- src/build/p3_async_manifest.zig — parse/free/validate the private
  future_owned canonical object and expose
  LoweringShape.future_owned_resource.
- src/build/p3_async_registry.json — register the exact
  do:future-owned-canonical/source@0.1.0#read descriptor.
- src/build/cli.zig — parse --p3-owned-future-component, enforce one special
  target, and add parser tests for acceptance/isolation.
- src/main.zig — include the target in build usage text.
- src/build/run.zig — pass the target through compilation and choose its WIT
  emitter for --p3-wit-output.
- src/build/codegen_pipeline.zig — add one isolated option and dispatch to the
  new analyzer/emitter pair.
- src/build/diag.zig — add the stable
  UnsupportedP3OwnedFutureComponent summary and hint.
- doc/pending_blocked.md, doc/host_abi_blockers.md, doc/roadmap_status.md —
  record the private promotion only after its gates pass.

Existing runtime evidence reused without changing its semantics:

- examples/p3-runtime/rust-host-runner/src/bin/future_owned_canonical_abi.rs
- examples/p3-runtime/test_future_owned_canonical_abi.sh
- examples/p3-runtime/wit/future-owned-canonical.wit

## Task 1: Extend the manifest with one private owned-future shape

**Interfaces:**

- Consumes: the existing Descriptor, Canonical, FutureCanonical, and
  LoweringShape parser contracts in src/build/p3_async_manifest.zig.
- Produces: FutureOwnedCanonical with fields resource, payload_offset,
  resource_offset, presence_offset, and drop_import, plus
  LoweringShape.future_owned_resource.

- [x] **Step 1: Add the failing manifest test.**

In src/build/p3_async_manifest.zig, add a JSON fixture containing the exact
descriptor from the design and assert:

~~~zig
const descriptor = registry.find(
    "do:future-owned-canonical/source@0.1.0",
    "read",
) orelse return error.TestExpectedEqual;
const shape = lowering_shape(descriptor) orelse return error.TestExpectedEqual;
switch (shape) {
    .future_owned_resource => |owned| {
        try std.testing.expectEqual(@as(u32, 12), owned.payload_offset);
        try std.testing.expectEqual(@as(u32, 16), owned.resource_offset);
        try std.testing.expectEqual(@as(u32, 20), owned.presence_offset);
    },
    else => return error.TestExpectedEqual,
}
~~~

Also add malformed cases for payload_offset=16, missing presence_offset, and a
different [resource-drop] name; each must return error.InvalidP3AsyncManifest
or a null lowering shape before codegen.

- [x] **Step 2: Run the focused test and verify it fails.**

Run from src/build:

~~~bash
zig test p3_async_manifest.zig
~~~

Expected: the new test does not compile because the JSON field and lowering
shape do not exist yet.

- [x] **Step 3: Implement the manifest record and parser.**

Add FutureOwnedCanonical beside the other canonical records, add the optional
field to Canonical, parse and free it in parse_canonical/free_canonical, and
add this exact branch before the existing generic effect == "async" branches:

~~~zig
if (std.mem.eql(u8, descriptor.effect, "future-owned-resource")) {
    const owned = descriptor.canonical.future_owned orelse return null;
    if (descriptor.params.len != 0 or
        !std.mem.eql(u8, descriptor.result, "Ticket") or
        !std.mem.eql(u8, owned.resource, "ticket") or
        owned.payload_offset != 12 or
        owned.resource_offset != 16 or
        owned.presence_offset != 20 or
        !std.mem.eql(u8, owned.drop_import, "[resource-drop]ticket")) return null;
    return .{ .future_owned_resource = owned };
}
~~~

Keep all existing descriptor branches unchanged.

- [x] **Step 4: Run the focused test and verify it passes.**

~~~bash
zig test p3_async_manifest.zig
~~~

Expected: existing manifest tests and the new positive/malformed tests pass.

- [x] **Step 5: Add the registry descriptor.**

Insert the exact JSON object from the design into
src/build/p3_async_registry.json. Keep descriptor order stable and do not
change existing SHA or descriptor fields.

- [x] **Step 6: Re-run the manifest suite and check formatting.**

~~~bash
zig test p3_async_manifest.zig
git diff --check
~~~

Expected: all manifest tests pass and no whitespace errors are reported.

## Task 2: Add the isolated CLI and pipeline target

**Interfaces:**

- Consumes: the existing cli.Args, EmitOptions, compile_program_wat_parts, and
  WIT emitter selection.
- Produces: Args.p3_owned_future_component, one mutually exclusive target,
  codegen.emit_p3_owned_future_component_wit, and
  UnsupportedP3OwnedFutureComponent diagnostics.

- [x] **Step 1: Add parser and pipeline failing tests.**

Extend src/build/cli.zig tests with:

~~~zig
test "parse_build accepts the private owned future component target" {
    const args = [_][]const u8{
        "build", "app.do", "--p3-owned-future-component",
        "--p3-wit-output", "app.wit",
    };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.p3_owned_future_component);
    try std.testing.expectEqualStrings("app.wit", parsed.p3_wit_output_path.?);
}

test "parse_build rejects owned future target combinations" {
    const args = [_][]const u8{
        "build", "app.do", "--p3-owned-future-component",
        "--p3-async-component-v2",
    };
    try std.testing.expectError(error.UnexpectedCliArg, parse_build(&args));
}
~~~

- [x] **Step 2: Run the CLI test and verify it fails.**

~~~bash
zig test cli.zig
~~~

Expected: the new field is missing and the acceptance test fails to compile.

- [x] **Step 3: Implement flag parsing and option plumbing.**

Add the boolean to cli.Args, parse the exact flag, include it in the
component_core/host_export guard, special-target count, WIT-output guard, and
returned Args. Thread the boolean through run.compile_program_wat and
compile_program_wat_parts, then add it to codegen.EmitOptions and the pipeline
dispatch. Update src/main.zig usage text.

The new dispatch must be a distinct branch:

~~~zig
if (options.p3_owned_future_component) {
    var plan = codegen_component_future_owned_plan.analyze(allocator, tokens) catch |err| {
        return err;
    };
    defer plan.deinit(allocator);
    return codegen_component_future_owned.emit_component_wat(allocator, plan);
}
~~~

It must not call the v1, async-call, or v2 emitters.

- [x] **Step 4: Add diagnostic text.**

Add these exact mappings in src/build/diag.zig:

~~~zig
error.UnsupportedP3OwnedFutureComponent =>
    "此 P3 Component 目标只支持 private Future<Ticket> -> future<own<ticket>> 源码形态",
~~~

and the hint:

~~~zig
error.UnsupportedP3OwnedFutureComponent =>
    "仅使用已注册的 Future<Ticket>、单次 @await 与 --p3-owned-future-component；own/borrow/ref 不是 Do 源码语法",
~~~

- [x] **Step 5: Run parser/pipeline tests.**

~~~bash
zig test cli.zig
zig test codegen_pipeline.zig
git diff --check
~~~

Expected: the new target tests pass and existing target-isolation tests remain
green.

## Task 3: Implement exact source admission

**Interfaces:**

- Consumes: lexer tokens and the registry descriptor from Task 1 (loaded by
  the plan module from the embedded registry JSON).
- Produces: FutureOwnedPlan.analyze(allocator, tokens) and
  FutureOwnedPlan.deinit, returning only the exact positive shape or
  error.UnsupportedP3OwnedFutureComponent.

- [x] **Step 1: Add positive and negative analyzer tests.**

In src/build/codegen_component_future_owned_plan_test.zig, define the positive
source exactly as follows:

~~~do
read = @host("do:future-owned-canonical/source@0.1.0", "read", () -> Future<Ticket>)
Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })
run(mode u32) -> nil {
    pending Future<Ticket> = read()
    ticket Ticket = @await(pending)
}
start() {}
~~~

Assert that the plan records the root name, mode parameter, descriptor, future
local, await state, and the three private frame offsets. Add one test for each
negative fixture class: unknown locator, Future<i32>, missing resource
declaration, two awaits, branch, helper function, and async run.

- [x] **Step 2: Run the analyzer tests and verify they fail.**

~~~bash
zig test codegen_component_future_owned_plan_test.zig
~~~

Expected: the module and FutureOwnedPlan symbols are missing.

- [x] **Step 3: Implement guard-style admission.**

Implement small token scanners for the host binding, exact resource declaration,
root function, future declaration, and await expression. Reject at the first
failed guard. Require the descriptor's LoweringShape to be
future_owned_resource; do not infer ownership from a type-name string.

The analyzer must reject all additional top-level functions and all body tokens
outside the one declaration, future binding, await, and closing brace. It must
return the exact error UnsupportedP3OwnedFutureComponent for every shape
failure.

- [x] **Step 4: Run analyzer tests and compile-error fixtures.**

~~~bash
zig test codegen_component_future_owned_plan_test.zig
for source in \
  src/build/test/compile_err/444_future_owned_component_unregistered.do \
  src/build/test/compile_err/445_future_owned_component_payload.do \
  src/build/test/compile_err/446_future_owned_component_two_awaits.do; do
  stderr=$(mktemp)
  if DO_LIB_ROOT="$PWD/lib" ./bin/do build "$source" \
      --p3-owned-future-component --p3-wit-output /tmp/future-owned.wit \
      -o /tmp/future-owned.wat 2>"$stderr"; then
    rm -f "$stderr"
    exit 1
  fi
  grep -Fq UnsupportedP3OwnedFutureComponent "$stderr"
  rm -f "$stderr"
done
~~~

Expected: all positive/negative analyzer assertions pass and each target build
matches UnsupportedP3OwnedFutureComponent. These fixtures are not ordinary
do check cases because the rejection belongs to the opt-in build target.

## Task 4: Emit the private WAT and WIT shape

**Interfaces:**

- Consumes: FutureOwnedPlan and FutureOwnedCanonical from Tasks 1 and 3.
- Produces: deterministic WAT with the measured frame protocol and a WIT
  sidecar byte-identical to future-owned-component.wit.

- [x] **Step 1: Add emitter tests before implementation.**

In src/build/codegen_component_future_owned_test.zig, assert that emitted WAT
contains these markers and imports:

~~~text
[future-owned-payload]
[future-owned-ticket-present]
[future-owned-transfer]
[future-owned-resource-drop]
[future-owned-cancel]
[task-return]run
[resource-drop]ticket
~~~

Also assert that it does not contain [task-return]helper,
[async-lift]helper, future<borrow<, or a public own<T> token in Do
source-derived output. Assert the WIT emitter equals the pinned snapshot.

- [x] **Step 2: Run the emitter tests and verify they fail.**

~~~bash
zig test codegen_component_future_owned_test.zig
~~~

Expected: the emitter module is missing.

- [x] **Step 3: Implement the WIT emitter.**

Emit exactly:

~~~wit
package do:future-owned-canonical@0.1.0;

interface source {
  resource ticket {}
  read: func() -> future<own<ticket>>;
}

interface probe {
  run: async func(mode: u32);
}

world future-owned-canonical {
  import source;
  export probe;
}
~~~

Keep this string in the new module and expose
emit_component_wit(allocator) through codegen_pipeline.zig.

- [x] **Step 4: Implement the WAT lifecycle.**

Start from the verified future-owned-canonical.wat frame protocol and make the
emitter substitute only the plan's exact root/import identity. Preserve:

- frame offsets +12, +16, +20;
- separate readable-future drop and resource-drop paths;
- payload transfer before cleanup;
- representation 0 as valid when +20 is set;
- cancellation code 2 without resource creation/drop;
- root-only [task-return]run and no internal task-return endpoint.

Use existing pure WAT fragments and ownership helpers only where they do not
change their admission rules.

- [x] **Step 5: Run emitter tests and parse the output.**

~~~bash
zig test codegen_component_future_owned_test.zig
test -x "$(command -v wasm-tools)"
~~~

Expected: unit tests pass; the WAT parses after the focused gate in Task 5
assembles it into a Component.

## Task 5: Add compiler-generated assembly and target-isolation gates

**Interfaces:**

- Consumes: the positive fixture, emitter, registry, and pinned toolchain.
- Produces: one shell gate proving sidecar identity, WAT markers, Component
  assembly, and isolation from v1/v2.

- [x] **Step 1: Add the positive fixture and WIT snapshot.**

Create examples/p3-runtime/future-owned-component.do with the exact source from
Task 3 and copy the exact WIT text from Task 4 into
examples/p3-runtime/future-owned-component.wit.

- [x] **Step 2: Write the failing shell gate.**

test_do_future_owned_component.sh must:

~~~bash
"$do_bin" build "$source" --p3-owned-future-component \
  --p3-wit-output "$wit" -o "$core_wat"
cmp "$wit_snapshot" "$wit"
grep -Fq '[future-owned-transfer]' "$core_wat"
grep -Fq '[future-owned-ticket-present]' "$core_wat"
if grep -Fq '[task-return]helper' "$core_wat"; then exit 1; fi
~~~

Then run wasm-tools 1.255.0 parse. For Component assembly, pass the existing
pinned legacy wasm-tools 1.254.0 binary through the same helper used by the
async-call gate, because current legacy async metadata is not interchangeable
with the 1.255.0 capability probe. Validate the assembled component with
--features cm-async,cm-more-async-builtins.

- [x] **Step 3: Run the gate and verify it fails before implementation.**

~~~bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 \
  bash examples/p3-runtime/test_do_future_owned_component.sh
~~~

Expected: the binary rejects the new flag because Task 2/4 is incomplete.

- [x] **Step 4: Add target-isolation assertions.**

Compile the same fixture with --p3-async-component and
--p3-async-component-v2 in temporary files. Require either a named rejection or
successful WAT without any [future-owned-*] markers. Compile with
--component-core and --host-export and require UnexpectedCliArg.

- [x] **Step 5: Run the completed assembly gate.**

~~~bash
WASM_TOOLS_EXPECT_VERSION=1.255.0 \
  bash examples/p3-runtime/test_do_future_owned_component.sh
~~~

Expected: sidecar comparison, WAT parse, Component assembly, validation, and
target isolation all pass.

## Task 6: Run the Rust/Wasmtime ready/pending/cancel matrix

**Interfaces:**

- Consumes: the Component produced by Task 5 and the existing
  future_owned_canonical_abi host contract.
- Produces: compiler-generated runtime evidence with exact cleanup counts.

- [x] **Step 1: Add the Rust wrapper gate.**

Create examples/p3-runtime/test_rust_future_owned_component.sh that invokes the
existing runner for ready, pending, and cancel and checks:

~~~text
mode=ready ... future-drops=1 ... resource-created=1 resource-drops=1 table-empty=true
mode=pending ... polls=2 ... future-drops=1 ... resource-drops=1 table-empty=true
mode=cancel ... cancel-calls=1 ... pending-future-drops=1 resource-created=0 resource-drops=0 table-empty=true
~~~

The runner must continue to exercise representation 0; do not use a nonzero
handle sentinel.

- [x] **Step 2: Run the runtime gate before wiring the compiler output.**

~~~bash
bash examples/p3-runtime/test_future_owned_canonical_abi.sh
~~~

Expected: the existing hand-written runtime evidence remains green.

- [x] **Step 3: Run the wrapper against the compiler-generated Component.**

The compiler gate must pass its concrete component path to the wrapper in the
same temporary directory:

~~~bash
bash examples/p3-runtime/test_rust_future_owned_component.sh "$component_path"
~~~

The combined gate must pass ready, pending, and cancel with one source call,
one future drop, exactly-once resource drop when created, zero resource drop
on cancellation, and an empty resource table.

## Task 7: Add focused regression fixtures and documentation

**Interfaces:**

- Consumes: all compiler and runtime gates from Tasks 1–6.
- Produces: stable negative diagnostics and an accurate project status.

- [x] **Step 1: Add negative fixtures and expected diagnostics.**

Populate the three files listed in the File Map with one invalid change each:

~~~do
// 444: use an unregistered locator
read = @host("do:future-owned-canonical/source@0.1.0", "missing", () -> Future<Ticket>)
~~~

~~~do
// 445: change the payload to a copied scalar
read = @host("do:future-owned-canonical/source@0.1.0", "read", () -> Future<i32>)
~~~

~~~do
// 446: add a second future/await sequence to run
second Future<Ticket> = read()
second_ticket Ticket = @await(second)
~~~

Each .expect contains UnsupportedP3OwnedFutureComponent and no unstable
line-specific text.

- [x] **Step 2: Update status documents after all focused gates pass.**

Record the exact target, private descriptor, pinned evidence, and acceptance
matrix in doc/pending_blocked.md, doc/host_abi_blockers.md, and
doc/roadmap_status.md. Keep generic Future<T>, owned streams,
borrowed-future/stream, producer expressions, and D2 async I/O explicitly
pending.

- [x] **Step 3: Run the complete verification set.**

~~~bash
cd src && zig build -Doptimize=ReleaseSmall
zig test build/cli.zig
zig test build/p3_async_manifest.zig
zig test build/codegen_component_future_owned_plan_test.zig
zig test build/codegen_component_future_owned_test.zig
cd ..
WASM_TOOLS_EXPECT_VERSION=1.255.0 \
  bash examples/p3-runtime/test_do_future_owned_component.sh
bash examples/p3-runtime/test_future_owned_canonical_abi.sh
./src/build/test/run_tests.sh
git diff --check
~~~

Expected: every focused gate and the full regression pass; any pre-existing
Cargo formatting drift is reported separately and is not silently changed.

- [x] **Step 4: Inspect scope before delivery.**

~~~bash
git diff --stat
git status --short
~~~

Confirm the diff contains only the new private target, its tests/gates, and the
status documents attributable to this plan. Do not commit or push until the user
reviews the design and explicitly requests delivery.
