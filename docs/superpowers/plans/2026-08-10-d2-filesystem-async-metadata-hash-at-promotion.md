# D2 descriptor.metadata-hash-at Private Promotion Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (- [ ]) syntax for tracking.

**Goal:** Privately promote the pinned descriptor.metadata-hash-at async
filesystem shape through --p3-async-component, with exact source admission,
path-copy evidence, Component validation, and Rust/Wasmtime cleanup coverage.

**Architecture:** Add a descriptor-specific manifest shape, sema signature
matcher, source planner, and independent Core WAT adapter. Keep the target in
the existing unified Component route; ordinary builds and unrelated async
descriptors remain fail-closed. The runtime oracle proves that the host binding
copies the UTF-8 path before its delayed future poll and that descriptor/task
cleanup is exactly once.

**Tech Stack:** Zig 0.16.0, wasm-tools 1.255.0, WIT, Core WAT, Rust 1.97.1,
Wasmtime 47.0.2, Bash, and the existing do regression harness.

## Global Constraints

- Use package wasi:filesystem@0.3.0-rc-2025-09-16 and upstream WIT SHA-256
  8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f.
- Require wasm-tools 1.255.0 (76e20611d 2026-07-30) with executable SHA-256
  6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013.
- Keep regular/cancel mirror hashes
  95e24b70eeed89407706c18a6e4cd13a8bc4dce72d1e56638436b03287d23412 and
  aca9c5933786a00a2dd20b1ad1ddbb6d0a79ab5b3bdbd5bd61e14b100a3b6e0a.
- Do not add public Result<T,E>, own<T>, borrow<T>, ref<T>, pointer, reference,
  lifetime, or generic async syntax.
- Keep compiler admission behind --p3-async-component; do not add a new CLI
  flag and do not change ordinary AsyncLoweringUnavailable behavior.
- Admit only (Dir, u32, text) -> MetadataHash | HashError, one direct await,
  one exact resource shell, and the ordinary synchronous run plus empty start
  shape.
- The host async binding copies path bytes into an owned Rust String before
  returning its future; guest frame fields retain only immutable call metadata.
- Cancellation is cleanup-only. Never synthesize rollback for a filesystem
  operation already issued to the host.
- A failed ABI, host-copy, cleanup, or Component gate leaves this method
  ABI-only and updates blocker documentation instead of widening the compiler.

## File Map

Runtime and probe inputs already exist and remain unchanged:

- examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at.wit
- examples/p3-runtime/wit/wasi-filesystem-metadata-hash-at-cancel.wit
- examples/p3-runtime/wasi-filesystem-metadata-hash-at.core.wat
- examples/p3-runtime/wasi-filesystem-metadata-hash-at-cancel.core.wat
- examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_at_abi.sh

Runtime files to create:

- examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_metadata_hash_at.rs
- examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash_at.sh

Compiler files to create:

- src/build/codegen_component_wasi_filesystem_metadata_hash_at.zig
- src/build/wasi_filesystem_metadata_hash_at_component_template.wat
- src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.do
- src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.expect
- src/build/test/compile_err/521_wasi_filesystem_metadata_hash_at_unregistered.do
  and matching .expect
- src/build/test/compile_err/522_wasi_filesystem_metadata_hash_at_wrong_flags.do
  and matching .expect
- src/build/test/compile_err/523_wasi_filesystem_metadata_hash_at_wrong_path.do
  and matching .expect
- src/build/test/compile_err/524_wasi_filesystem_metadata_hash_at_wrong_result.do
  and matching .expect
- src/build/test/compile_err/525_wasi_filesystem_metadata_hash_at_second_await.do
  and matching .expect
- src/build/test/compile_err/526_wasi_filesystem_metadata_hash_at_branch.do
  and matching .expect
- src/build/test/compile_err/527_wasi_filesystem_metadata_hash_at_loop.do
  and matching .expect
- src/build/test/compile_err/528_wasi_filesystem_metadata_hash_at_extra_host.do
  and matching .expect
- src/build/test/compile_err/529_wasi_filesystem_metadata_hash_at_async_root.do
  and matching .expect

Compiler files to modify:

- src/build/p3_async_registry.json
- src/build/p3_async_manifest.zig
- src/build/sema_imports.zig
- src/build/codegen_component_async.zig

Status documentation to modify only after all gates pass:

- doc/host_abi_blockers.md
- doc/pending_blocked.md

The CLI argument model, src/build/run.zig, codegen_model.EmitOptions, and
generic Core emitter are intentionally not modified.

---

### Task 1: Freeze the baseline and verify the ABI-only starting point

**Files:**
- Read: docs/superpowers/specs/2026-08-10-d2-filesystem-async-metadata-hash-at-promotion-design.md
- Read: the existing ABI WIT/Core/script files listed above
- Test: repository baseline commands

**Interfaces:**
- Consumes: the committed ABI probe at d72a432.
- Produces: command-backed baseline evidence; no source changes.

- [ ] Step 1: Verify checkout and pinned inputs.

Run:

~~~bash
git status --short --branch
wasm-tools --version
sha256sum "$(command -v wasm-tools)"
sha256sum src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit
~~~

Expected: clean worktree, main ahead of origin/main only by existing local
commits, and the exact versions/hashes in the global constraints.

- [ ] Step 2: Run the existing ABI and compiler baselines.

Run:

~~~bash
bash examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_at_abi.sh
./src/build/test/run_tests.sh
cd src && zig test main.zig
~~~

Expected: the ABI probe and existing regression pass before any compiler
change. Preserve a complete failure as a blocker rather than masking it with a
new test command.

- [ ] Step 3: Record the baseline checkpoint.

Write the command results into the task notes and continue only if the ABI gate
is green. Do not commit a code change in this task.

### Task 2: Add the Rust/Wasmtime path-copy and cleanup oracle

**Files:**
- Create: examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_metadata_hash_at.rs
- Create: examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash_at.sh
- Read: examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_metadata_hash.rs
- Read: examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_get_flags.rs

**Interfaces:**
- Consumes: regular/cancel WIT and Core probe worlds.
- Produces: binary wasi-filesystem-metadata-hash-at accepting
  <component.wasm> <mode>, with modes ready, pending, error, cancel,
  early-drop, and repeat.

- [ ] Step 1: Write the host binding and counters.

Use the existing metadata-hash runner structure. Define a PathFlags Component
flags type with the single symlink-follow member, the existing MetadataHash
record and complete ErrorCode enum, plus counters for host calls, observed
flags, observed path, polls, wakes, completions, future drops, pending future
drops, and descriptor drops.

The async host registration must have this shape:

~~~rust
types.func_wrap_concurrent(
    "[method]descriptor.metadata-hash-at",
    move |accessor, (descriptor, path_flags, path): (
        Resource<Descriptor>,
        PathFlags,
        String,
    )| {
        // Copy path and flags into the future before returning it.
        Box::pin(MetadataHashAtFuture { path, path_flags, /* counters */ })
    },
)?;
~~~

The future stores the owned String and reads it only after the configured
pending wake. It must never retain a guest pointer.

- [ ] Step 2: Add the mode matrix.

Implement these assertions:

~~~text
ready: Ok(expected hash), one call, one poll, zero external wakes
pending: Ok(expected hash), one external wake, two polls, exact UTF-8 path
error: Err(no-entry), one completion, no fabricated record
cancel: no completion, one pending future drop, one descriptor drop
early-drop: store-discarded, pending future drop, table-empty=not-applicable
repeat: two Ok results, two calls, two future drops, two descriptor drops
~~~

Use a non-ASCII path such as probe-utf8 in the pending row and verify the host
observes the same UTF-8 string after the wake.

- [ ] Step 3: Add the runtime gate script.

The script must pin wasm-tools and all WIT/Core hashes, parse and validate both
hand-authored Core modules, embed/new/validate both Components, run
rustfmt --edition 2024 --check, and invoke Cargo with the existing Zig C
linker environment. Compare complete counter lines, not only exit status.

Run:

~~~bash
bash examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash_at.sh
~~~

Expected: every live-Store mode has exactly-once host future and descriptor
cleanup; the early-drop row explicitly reports table-empty=not-applicable.

- [ ] Step 4: Commit the independent runtime oracle.

~~~bash
git add examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_metadata_hash_at.rs \
  examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash_at.sh
git commit -m "Add metadata-hash-at runtime oracle"
~~~

### Task 3: Add red compiler fixtures before admission code

**Files:**
- Create: src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.do
- Create: src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.expect
- Create: compile-error fixtures 521-529 and matching expectations from the File Map
- Read: existing fixtures 516-519 and 498-510

**Interfaces:**
- Consumes: the current fail-closed registry/sema behavior.
- Produces: exact source-shape regression cases for the new planner.

- [ ] Step 1: Add the positive source fixture.

Use the exact source contract from the spec, with a normal synchronous
run(file Dir, path_flags u32, path text) and one direct await:

~~~do
metadata_hash_at = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.metadata-hash-at", (Dir, u32, text) -> MetadataHash | HashError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
MetadataHash = @wasi_record("filesystem/types/metadata-hash-value", { lower u64, upper u64 })
HashError error = Io | NoEntry
run(file Dir, path_flags u32, path text) -> MetadataHash | HashError {
    pending Future<MetadataHash | HashError> = metadata_hash_at(file, path_flags, path)
    return @await(pending)
}
start() {}
~~~

- [ ] Step 2: Add negative source fixtures.

Base each case on the positive fixture and make only the named drift:

~~~text
521: member descriptor.metadata-hash-at is absent from the registry
522: replace u32 path-flags with text
523: replace text path with u32
524: replace the MetadataHash result with a scalar result
525: await the same pending Future twice
526: add a branch before the await
527: add a loop before the await
528: add an unrelated host binding
529: mark run as async
~~~

Use these expected diagnostics, matching existing fixture conventions:
UnknownP3AsyncHostDescriptor for 521, P3AsyncHostSignatureMismatch for 522-524,
FutureAlreadyConsumed for 525, and UnsupportedP3AsyncComponent for 526-529.
Every expectation file must contain # build-arg: --p3-async-component.

- [ ] Step 3: Run the red fixture gate.

Run:

~~~bash
DO_LIB_ROOT="$PWD/lib" ./bin/do build \
  src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.do \
  --p3-async-component -o /tmp/metadata-hash-at-red.wat
./src/build/test/run_tests.sh
~~~

Expected before Task 4: the positive fixture fails because the descriptor is
not registered, while all negative fixtures fail for their declared
diagnostics. If a failure is caused by a fixture typo rather than missing
capability, fix the fixture before proceeding.

### Task 4: Register and unit-test the exact manifest shape

**Files:**
- Modify: src/build/p3_async_registry.json
- Modify: src/build/p3_async_manifest.zig

**Interfaces:**
- Consumes: ABI facts from Task 1 and source fixtures from Task 3.
- Produces: LoweringShape.filesystem_metadata_hash_at carrying the exact
  receiver, source path types, result identity, record layout, canonical words,
  async import name, and descriptor drop import.

- [ ] Step 1: Add the registry entry.

Insert a separate descriptor entry with these exact values:

~~~json
{
  "locator": "wasi:filesystem/types@0.3.0-rc-2025-09-16",
  "member": "descriptor.metadata-hash-at",
  "effect": "async",
  "params": ["descriptor", "path-flags", "string"],
  "result": "Result<metadata-hash-value,error-code>",
  "resource": null,
  "wit_sha256": "8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f",
  "canonical": {
    "core_params": ["i32", "i32", "i32", "i32", "i32"],
    "core_results": ["i32"],
    "completion_params": ["i32", "i64", "i64"],
    "completion": "task-return",
    "record_layout": {
      "name": "metadata-hash-value",
      "byte_size": 16,
      "fields": [
        {"name": "lower", "core_type": "i64", "offset": 0},
        {"name": "upper", "core_type": "i64", "offset": 8}
      ],
      "source_fields": [
        {"name": "lower", "source_type": "u64", "storage": ["lower"]},
        {"name": "upper", "source_type": "u64", "storage": ["upper"]}
      ]
    },
    "async_import_module": "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "async_import_name": "[async-lower][method]descriptor.metadata-hash-at"
  },
  "wit": {
    "package": "wasi:filesystem@0.3.0-rc-2025-09-16",
    "interface": "types",
    "operation": "descriptor.metadata-hash-at",
    "world": "imports",
    "parameter": ""
  }
}
~~~

- [ ] Step 2: Add the manifest shape and fail-closed matcher.

Add filesystem_metadata_hash_at: FilesystemMetadataHashAtShape to the
LoweringShape union and a dedicated validator. Require the exact WIT hash,
five i32 core params, one i32 core result, three task-return words, 16-byte
lower/upper layout, and the canonical async import. Do not accept a generic
record result as this shape.

- [ ] Step 3: Add manifest tests.

Add tests that accept the checked-in descriptor and assert receiver/path/result
fields, then reject one changed core parameter, one changed WIT hash, reordered
metadata-hash-value fields, and a changed async import name.

Run:

~~~bash
cd src && zig test build/p3_async_manifest.zig
~~~

Expected: all manifest tests pass and existing descriptor shape tests remain
green.

- [ ] Step 4: Commit the registry boundary.

~~~bash
git add src/build/p3_async_registry.json src/build/p3_async_manifest.zig
git commit -m "Register metadata-hash-at ABI shape"
~~~

### Task 5: Add sema admission for the mixed source signature

**Files:**
- Modify: src/build/sema_imports.zig

**Interfaces:**
- Consumes: LoweringShape.filesystem_metadata_hash_at.
- Produces: exact (Dir, u32, text) -> MetadataHash | HashError host-import
  validation before planner/codegen.

- [ ] Step 1: Add the dedicated matcher.

Add filesystem_metadata_hash_at_signature_matches beside the existing
filesystem matchers. Check the parameter token sequence ( Dir , u32 , text )
and compare the result token range with MetadataHash|HashError. Do not route
this through the generic parameter loop, because the source names and result
union are part of this pinned shape.

- [ ] Step 2: Dispatch the new shape.

Add a .filesystem_metadata_hash_at arm to p3_async_signature_matches. Keep the
existing metadata_hash and stat arms unchanged.

- [ ] Step 3: Verify sema diagnostics.

Run:

~~~bash
cd src && zig test build/sema_imports.zig
DO_LIB_ROOT="$PWD/../lib" ../bin/do build \
  ../src/build/test/compile_err/522_wasi_filesystem_metadata_hash_at_wrong_flags.do \
  --p3-async-component -o /tmp/metadata-hash-at-sema.wat
~~~

Expected: focused Zig tests pass and the wrong-flags fixture reports
P3AsyncHostSignatureMismatch.

### Task 6: Implement the independent planner and Core WAT adapter

**Files:**
- Create: src/build/codegen_component_wasi_filesystem_metadata_hash_at.zig
- Create: src/build/wasi_filesystem_metadata_hash_at_component_template.wat

**Interfaces:**
- Consumes: manifest shape and sema-approved tokens.
- Produces: MetadataHashAtPlan.analyze(tokens, registry) ->
  MetadataHashAtPlan, emit_component_wat(allocator, program, tokens,
  module_graph) -> []u8, and emit_component_wit(allocator, tokens) -> []u8.

- [ ] Step 1: Write planner tests first.

Embed fixture 520 and assert that the plan captures the host alias, root name,
file/flags/path parameter names, and pending local. Embed fixtures 525, 526,
527, 528, and 529 and assert
UnsupportedP3WasiFilesystemMetadataHashAtComponent. Assert reordered record
fields and a second matching host binding are rejected before template loading.

- [ ] Step 2: Implement exact source analysis.

Mirror MetadataHashPlan but require:

~~~text
exact locator/member and registry shape
exactly one @host_async_func binding
exact signature (Dir, u32, text) -> MetadataHash | HashError
exact Dir, MetadataHash, and HashError declarations
exact synchronous run with one metadata_hash_at call and one @await
exactly two function definitions and empty start
~~~

Return a dedicated error named
UnsupportedP3WasiFilesystemMetadataHashAtComponent for every mismatch.

- [ ] Step 3: Add the WAT template.

Use the measured imports and frame offsets from the spec. Include these markers
in source order:

~~~text
[metadata-hash-at-call]
[metadata-hash-at-result-area]
[metadata-hash-at-ready]
[metadata-hash-at-error]
[metadata-hash-at-pending]
[descriptor-drop]
~~~

The start function passes descriptor, flags, path pointer, path length, and
result-area pointer to the five-i32 method import. The callback reads the
16-byte record or error payload before dropping the subtask, descriptor,
waitable, and context. It must not allocate or copy an arbitrary second path
buffer. The test-only cancel template remains the existing hand-authored
artifact; the compiler adapter emits the regular world only.

- [ ] Step 4: Add adapter WIT and WAT tests.

Assert the generated WIT contains:

~~~wit
metadata-hash-at: async func(path-flags: path-flags, path: string) -> result<metadata-hash-value, error-code>;
run: async func(file: own<descriptor>, path-flags: path-flags, path: string) -> result<metadata-hash-value, error-code>;
~~~

Assert WAT contains the five-i32 method type, task-return (i32 i64 i64),
path frame offsets, result-area marker, and one descriptor drop import.

### Task 7: Wire target classification and generated compiler output

**Files:**
- Modify: src/build/codegen_component_async.zig
- Test: fixtures 520-529 and focused Zig tests
- Read-only check: src/build/codegen_pipeline.zig, src/build/run.zig,
  src/build/cli.zig

**Interfaces:**
- Consumes: MetadataHashAtPlan and manifest shape.
- Produces: Target.wasi_filesystem_metadata_hash_at through the existing
  unified --p3-async-component target.

- [ ] Step 1: Add target dispatch.

Import the adapter, add the enum value, and add independent arms to
emit_component_wat, emit_component_wit, token classification, and
target_for_descriptor. The token classifier must require host_async_func and
MetadataHashAtPlan.analyze; a matching descriptor with any other source shape
returns UnsupportedP3AsyncComponent.

- [ ] Step 2: Add target tests.

Add tests asserting fixture 520 maps to
Target.wasi_filesystem_metadata_hash_at, while record drift, fixture 525 second
await, and fixture 529 async root do not map to the new target.

Run:

~~~bash
cd src && zig test build/codegen_component_async.zig
DO_LIB_ROOT="$PWD/../lib" ../bin/do build \
  ../src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.do \
  --p3-async-component --p3-wit-output /tmp/metadata-hash-at.wit \
  -o /tmp/metadata-hash-at.wat
~~~

Expected: target tests pass, generated WAT contains independent markers, and
generated WIT contains the exact path-flags/string operation.

- [ ] Step 3: Keep the CLI surface unchanged.

Run:

~~~bash
cd src && zig test build/cli.zig
~~~

Expected: no new flag is present; the existing unified target remains the only
entrypoint. Do not edit Args, EmitOptions, or run.zig for this shape.

- [ ] Step 4: Commit compiler admission.

~~~bash
git add src/build/codegen_component_wasi_filesystem_metadata_hash_at.zig \
  src/build/wasi_filesystem_metadata_hash_at_component_template.wat \
  src/build/codegen_component_async.zig \
  src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.do \
  src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.expect \
  src/build/test/compile_err/521_wasi_filesystem_metadata_hash_at_unregistered.* \
  src/build/test/compile_err/522_wasi_filesystem_metadata_hash_at_wrong_flags.* \
  src/build/test/compile_err/523_wasi_filesystem_metadata_hash_at_wrong_path.* \
  src/build/test/compile_err/524_wasi_filesystem_metadata_hash_at_wrong_result.* \
  src/build/test/compile_err/525_wasi_filesystem_metadata_hash_at_second_await.* \
  src/build/test/compile_err/526_wasi_filesystem_metadata_hash_at_branch.* \
  src/build/test/compile_err/527_wasi_filesystem_metadata_hash_at_loop.* \
  src/build/test/compile_err/528_wasi_filesystem_metadata_hash_at_extra_host.* \
  src/build/test/compile_err/529_wasi_filesystem_metadata_hash_at_async_root.*
git commit -m "Promote metadata-hash-at compiler shape"
~~~

### Task 8: Assemble generated Component and compare the runtime oracle

**Files:**
- Modify: examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash_at.sh
- Read: generated temporary WIT and WAT
- Use: examples/p3-runtime/assemble_async_component.sh

**Interfaces:**
- Consumes: compiler output from Task 7 and Rust oracle from Task 2.
- Produces: validated generated Component with runtime behavior matching the
  hand-authored regular ABI and cleanup counters.

- [ ] Step 1: Add compiler generation to the runtime script.

Generate WIT/WAT from fixture 520, assert generated WIT has path-flags:
path-flags and path: string, and assert generated WAT has the measured import,
five-i32 method type, path frame offsets, and task return.

- [ ] Step 2: Embed, assemble, and validate.

Run the repository's existing temporary-directory flow:

~~~bash
DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build \
  "$repo_root/src/build/test/compile_ok/520_wasi_filesystem_metadata_hash_at_component.do" \
  --p3-async-component --p3-wit-output "$tmp_dir/generated.wit" \
  -o "$tmp_dir/generated.core.wat"
wasm-tools parse "$tmp_dir/generated.core.wat" -o "$tmp_dir/generated.core.wasm"
wasm-tools component embed "$tmp_dir/generated-wit" "$tmp_dir/generated.core.wasm" \
  --world metadata-hash-at-probe --features cm-async,cm-more-async-builtins \
  -o "$tmp_dir/generated.embedded.wasm"
wasm-tools component new --skip-validation "$tmp_dir/generated.embedded.wasm" \
  -o "$tmp_dir/generated.component.wasm"
wasm-tools validate --features cm-async,cm-more-async-builtins \
  "$tmp_dir/generated.component.wasm"
~~~

Use the existing script's temporary WIT package layout and the pinned
wasm-tools binary; do not silently fall back to another toolchain.

- [ ] Step 3: Run generated and hand-authored modes.

Run the Rust runner for ready, pending, error, cancel, early-drop, and repeat
against the generated regular Component and the hand-authored cancel Component.
Compare path, flags, result, completion, future-drop, pending-drop,
descriptor-drop, and table-empty fields.

- [ ] Step 4: Commit the generated Component gate.

~~~bash
git add examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash_at.sh
git commit -m "Validate generated metadata-hash-at Component"
~~~

### Task 9: Update blocker status and run the complete delivery gates

**Files:**
- Modify: doc/host_abi_blockers.md
- Modify: doc/pending_blocked.md
- Verify: all changed files and git history

**Interfaces:**
- Consumes: command-backed evidence from Tasks 1-8.
- Produces: status documentation distinguishing the newly closed private
  method from still-blocked generic async, host I/O, and ownership work.

- [ ] Step 1: Update status docs with bounded claims.

Record only verified facts:

~~~text
descriptor.metadata-hash-at: private compiler admission and generated runtime
path: host String copy verified before delayed future poll
cancellation: cleanup-only; no host rollback
generic filesystem/HTTP async: still blocked
public own<T>/borrow<T>/ref<T>: unchanged and unsupported
~~~

Include exact scripts and pinned versions. Do not mark D2 or generic
AsyncLoweringUnavailable as closed.

- [ ] Step 2: Run focused and full verification.

Run:

~~~bash
bash examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_at_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash_at.sh
./src/build/test/run_tests.sh
cd src && zig test main.zig
cd .. && zig build -Doptimize=ReleaseSmall
git diff --check
~~~

Expected: all focused gates and the complete regression pass; no changed file
contains an incomplete marker, stale hash, or untracked fixture.

- [ ] Step 3: Review the final diff and commit documentation.

~~~bash
git status --short --branch
git diff --stat origin/main..HEAD
git diff --check origin/main..HEAD
git add doc/host_abi_blockers.md doc/pending_blocked.md
git commit -m "Record metadata-hash-at promotion status"
~~~

Keep the branch local until the user explicitly requests push. If a later
delivery request says push all, fetch/rebase first and then push the validated
main branch.
