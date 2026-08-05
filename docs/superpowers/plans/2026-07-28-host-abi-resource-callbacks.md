# Host ABI Resource And Callback ID Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `do`'s host boundary safe for concrete value types and non-capturing event callbacks without adding public pointer, reference, closure, or `funcref` syntax.

**Architecture:** Make `@host_func` the single host declaration form, replacing the current implementation's legacy `@host` path before extending host ABI behavior. Keep Core Wasm manifest generation as the boundary and make its ABI record the ownership and callback kind needed by adapters. Public host exports remain concrete value functions only; callback parameters are permanently rejected there. A guest-to-host callback lowers to a compiler-private static callback id plus a generated dispatcher export, while event registration is represented by an explicit host-owned subscription resource.

**Tech Stack:** Zig compiler and WAT emitter, Core WebAssembly, JSON manifest, Bun/TypeScript browser adapter tests, WIT/Component Model validation through existing `wasm-tools` gates.

## Global Constraints

- Do source gains no pointer, reference, closure, `funcref`, `externref`, or raw linear-memory pointer type.
- `@host_func(locator, member, signature)` is the only host function declaration form; legacy `@host` is migrated then rejected.
- A lambda cannot capture outer local bindings; callback identity is static code plus a per-instance id, not an ARC closure object.
- `--host-export` accepts concrete public value signatures only and rejects all function-type parameters.
- Host values crossing the JavaScript boundary use explicit copy, `own`, or call-scoped `borrow`; host code never fabricates or frees internal ARC handles directly.
- Resource destruction stays explicit (`unsubscribe`/`close`); dropping a Do value never implicitly invokes host cleanup.
- Reuse existing WIT resource conventions in `doc/wit/wasi_p3_lowering.md`; do not special-case UI function names.

---

## File Structure

- `src/build/host_export_abi.zig`: Shared concrete Core ABI collector and permanent exported-callback rejection.
- `src/build/host_export_manifest.zig`: Versioned manifest records for value ownership and callback/export exclusions.
- `src/build/host_callback_abi.zig`: New compiler-private static callback-id and dispatcher ABI collection.
- `src/build/codegen_emit_expression.zig`: Emit callback dispatcher exports and callback-id call arguments for registered host imports.
- `src/build/parser.zig`, `src/build/sema_imports.zig`, `src/build/codegen_host_imports.zig`: Migrate legacy `@host` declarations to documented `@host_func` before adding callback lowering.
- `src/build/codegen_host_imports.zig`: Lower the restricted inline callback parameter in an `@host_func` signature as a compiler-private static id.
- `src/build/codegen_pipeline.zig`: Install callback ABI records and emit dispatchers only for reachable registered callbacks.
- `src/build/test/compile_ok/341_*`: Core ABI and generic-struct manifest regression fixtures.
- `src/build/test/compile_err/340_*`: Callback export rejection and unsupported host callback mode fixtures.
- `src/build/test/run_tests.sh`: Run host-export negative fixtures with `--host-export` and check diagnostic expectations.
- `examples/ui-signal/host-runtime.ts`: New real Wasm adapter, callback registry, subscription cleanup, and instance disposal boundary.
- `examples/ui-signal/host-runtime.test.ts`: Adapter ownership, callback dispatch, cancellation, and disposal tests.
- `doc/host_abi_blockers.md`: Remove resolved blockers and retain only evidence-backed deferred work.
- `doc/host-binding-design.md`: Canonical JS/Core ABI ownership table and host adapter contract.
- `doc/wit/wasi_p3_lowering.md`: Map callback ids and subscriptions to Component Model resources/future-stream follow-up without exposing references.

## Task 1: Freeze The Boundary Contract And Negative Surface

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/host-binding-design.md`
- Modify: `src/build/host_export_abi.zig`
- Create: `src/build/test/compile_err/340_host_export_callback_param.do`
- Create: `src/build/test/compile_err/340_host_export_callback_param.expect`
- Modify: `src/build/test/run_tests.sh`

**Interfaces:**
- Produces: a documented `host-callback-v1` contract with `static-id` and `subscription` modes; no `retained closure` mode.
- Produces: `error.HostExportCallbackParamUnsupported` as a permanent public-export boundary.
- Produces: the host-signature-only callback grammar `(Event) -> nil`; it is never a stored resource or public callback type.

- [ ] **Step 1: Write the negative fixture and runner path**

```do
#F = (i32) -> nil
apply(f F) {
    f(1)
}
```

Add `HostExportCallbackParamUnsupported` to its `.expect`, and extend `run_tests.sh` so `compile_err/*.host_export.expect` invokes `do build --host-export` and matches stderr.

- [ ] **Step 2: Run the fixture before changing implementation**

Run: `./src/build/test/run_tests.sh`

Expected: the new fixture is not yet collected, proving the runner extension is necessary.

- [ ] **Step 3: Document the four terminal states**

Add a `host-callback-v1` table that fixes: `borrowed` is one host call only; `static-id` is callable while its Wasm instance is live; `unsubscribe` removes the host listener; `dispose(instance)` removes all remaining listeners before invalidating ids. State explicitly that a host-export function cannot accept a Do function value.

- [ ] **Step 4: Make the compiler guard intentional**

Keep the `param.callback != null` guard in `host_export_abi.validate_func`, add a short comment linking it to the contract, and add a Zig unit test asserting this error for a callback parameter.

- [ ] **Step 5: Run focused and integration checks**

Run: `cd src && zig test build/host_export_abi.zig && cd .. && ./src/build/test/run_tests.sh`

Expected: focused ABI test and all integration cases pass, including the new negative fixture.

- [ ] **Step 6: Commit**

```bash
git add doc/host_abi_blockers.md doc/host-binding-design.md src/build/host_export_abi.zig src/build/test/compile_err/340_host_export_callback_param.do src/build/test/compile_err/340_host_export_callback_param.expect src/build/test/run_tests.sh
git commit -m "docs: freeze host callback boundary"
```

## Task 2: Unify Concrete ABI Expansion For Generic Value Structs

**Files:**
- Create: `src/build/host_abi_types.zig`
- Modify: `src/build/host_export_abi.zig`
- Modify: `src/build/host_export_manifest.zig`
- Modify: `src/build/codegen_generics.zig`
- Create: `src/build/test/compile_ok/341_host_export_generic_struct.do`
- Create: `src/build/test/compile_ok/341_host_export_generic_struct.host_export.expect`
- Create: `src/build/test/compile_ok/341_host_export_generic_struct.host_manifest.expect`

**Interfaces:**
- Produces: `append_concrete_wasm_types(allocator, out, type_name, bindings, tokens, ctx)`.
- Consumes: post-monomorphization generic bindings used by normal WAT function emission.
- Produces: exactly one scalar sequence used by both emitted WAT signatures and manifest `wasm_params`/`wasm_results`.

- [ ] **Step 1: Add a failing generic unmanaged-struct host-export fixture**

```do
#T
Pair {
    left T
    right u8
}

echo(pair Pair<i32>) -> Pair<i32> {
    return pair
}
```

Expected manifest fragment: `"wasm_params":["i32","i32"]` and the same two-result WAT signature.

- [ ] **Step 2: Run the focused host-export fixture**

Run: `DO_LIB_ROOT=lib ./bin/do build src/build/test/compile_ok/341_host_export_generic_struct.do --host-export --host-manifest /tmp/generic-host.json -o /tmp/generic-host.wat`

Expected: FAIL with `HostExportGenericStructAbiUnsupported`.

- [ ] **Step 3: Extract the post-monomorphization collector**

Move only type-to-Core-Wasm expansion into `host_abi_types.zig`. It must recursively handle scalar, tuple, union, concrete unmanaged struct, and managed handle types, accepting the already-computed generic binding map instead of rereading declaration field text without substitutions.

- [ ] **Step 4: Route both consumers through the collector**

Replace duplicate expansion in `host_export_abi` and the corresponding generic function WAT signature path. Preserve all unsupported diagnostics for values that lack a concrete instance.

- [ ] **Step 5: Verify WAT and manifest from one fixture**

Run: `./src/build/test/run_tests.sh`

Expected: `341_*` checks both flattened WAT and manifest text; no existing component or compile fixture regresses.

- [ ] **Step 6: Commit**

```bash
git add src/build/host_abi_types.zig src/build/host_export_abi.zig src/build/host_export_manifest.zig src/build/codegen_generics.zig src/build/test/compile_ok/341_host_export_generic_struct.do src/build/test/compile_ok/341_host_export_generic_struct.host_export.expect src/build/test/compile_ok/341_host_export_generic_struct.host_manifest.expect
git commit -m "feat: expand concrete generic host ABI values"
```

## Task 3: Version The Canonical JavaScript Value ABI

**Files:**
- Modify: `src/build/host_export_manifest.zig`
- Modify: `doc/host-binding-design.md`
- Create: `src/build/test/compile_ok/342_host_value_ownership.do`
- Create: `src/build/test/compile_ok/342_host_value_ownership.host_manifest.expect`
- Modify: `examples/ui-signal/runtime.ts`
- Modify: `examples/ui-signal/runtime.test.ts`

**Interfaces:**
- Produces: manifest `abi: "core-wasm-v2"` entries with `value_mode` for every parameter/result: `scalar`, `flat-value`, `copy-text`, `copy-list-u8`, or `resource-own`.
- Produces: TypeScript `liftValue` and `lowerValue` that consume the manifest and never expose a Do ARC handle as a JavaScript value.

- [ ] **Step 1: Add the manifest expectation before adapter code**

Use a fixture exporting `text`, `Tuple<i32, u8>`, `Point`, and `File`-like resource values. Assert that `text` is `copy-text`, a flattened struct is `flat-value`, and a resource has `resource-own` plus a named explicit close operation.

- [ ] **Step 2: Run the fixture to establish the missing metadata**

Run: `DO_LIB_ROOT=lib ./bin/do build src/build/test/compile_ok/342_host_value_ownership.do --host-export --host-manifest /tmp/value-host.json -o /tmp/value-host.wat`

Expected: manifest lacks `value_mode` fields.

- [ ] **Step 3: Emit only canonical metadata, not JS-specific executable code**

Add per-value ownership records to `host_export_manifest`. `text` and byte lists must describe a copy boundary; a resource must name its `close` ABI operation; raw ARC `i32` stays an implementation detail.

- [ ] **Step 4: Add adapter conversion with cleanup guards**

In `examples/ui-signal/runtime.ts`, implement manifest-driven UTF-8 allocation/copy-out and use `try/finally` to release adapter-owned temporary values on all return, throw, and cancellation paths. Keep existing simulated runtime behavior unchanged until Task 5.

- [ ] **Step 5: Run TypeScript tests and compiler suite**

Run: `cd examples/ui-signal && bun run verify && cd ../.. && ./src/build/test/run_tests.sh`

Expected: 14 existing UI runtime checks and all compiler tests pass; new tests prove no raw ARC handle is observable.

- [ ] **Step 6: Commit**

```bash
git add src/build/host_export_manifest.zig doc/host-binding-design.md src/build/test/compile_ok/342_host_value_ownership.do src/build/test/compile_ok/342_host_value_ownership.host_manifest.expect examples/ui-signal/runtime.ts examples/ui-signal/runtime.test.ts
git commit -m "feat: define canonical host value ownership"
```

## Task 4: Lower Guest-To-Host Non-Capturing Callbacks To Static IDs

**Files:**
- Create: `src/build/host_callback_abi.zig`
- Modify: `src/build/codegen_context.zig`
- Modify: `src/build/codegen_host_imports.zig`
- Modify: `src/build/codegen_emit_expression.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/host_export_manifest.zig`
- Create: `src/build/test/compile_ok/343_host_static_callback.do`
- Create: `src/build/test/compile_ok/343_host_static_callback.expect`
- Create: `src/build/test/compile_ok/343_host_static_callback.host_manifest.expect`

**Interfaces:**
- Produces: `HostCallbackRecord { id: u32, signature_id: u32, target_name: []const u8 }`.
- Produces: generated internal export `__do_callback_invoke_v1(signature_id: i32, callback_id: i32, ...) -> status`.
- Consumes: a registered host import descriptor declaring `callback_mode: "static-id"`; unregistered imports with a callback parameter remain rejected.

- [ ] **Step 1: Add a positive callback fixture and exact WAT expectations**

```do
host_subscribe = @host_func(
    "host",
    "subscribe",
    (Button, (ClickEvent) -> nil) -> Subscription,
)

bind(button Button) -> Subscription {
    return host_subscribe(button, (event ClickEvent) => render(event))
}
```

`host_subscribe` is a host function and `Subscription` is its explicit resource result. The nested `(ClickEvent) -> nil` is a callback parameter form valid only inside an `@host_func` signature. The expectation must require an `i32` callback id in the host import call and the private dispatcher export; it must not contain `funcref`, `externref`, an ARC callback allocation, or a public `Callback` type.

- [ ] **Step 2: Run the fixture before implementation**

Run: `DO_LIB_ROOT=lib ./bin/do build src/build/test/compile_ok/343_host_static_callback.do -o /tmp/static-callback.wat`

Expected: FAIL because host callback imports have no registered static-id lowering.

- [ ] **Step 3: Collect only reachable non-capturing callback targets**

Create `host_callback_abi.zig` to assign deterministic ids from target name plus concrete callback signature. Reject any callback form that needs a value environment, and keep ids scoped to one instance/module build.

- [ ] **Step 4: Emit dispatcher and host import arguments**

Use the record list to emit a type-checked dispatcher branch per signature/id. Host imports receive the `i32` id only; callback arguments/results use the canonical value ABI from Task 3. Convert a callback trap to an explicit nonzero dispatcher status without silently continuing.

- [ ] **Step 5: Add manifest and focused Zig tests**

Manifest callback entries must expose `{ "kind": "static-id", "dispatcher": "__do_callback_invoke_v1", "signature": ... }`. Add unit tests for deterministic ids, signature mismatch rejection, and no callback entry for public host exports.

- [ ] **Step 6: Verify all compiler gates**

Run: `cd src && zig test build/codegen_api.zig && zig test build/host_export_manifest.zig && cd .. && ./src/build/test/run_tests.sh`

Expected: new fixture passes; no source-level Wasm reference type appears in emitted WAT or public manifest values.

- [ ] **Step 7: Commit**

```bash
git add src/build/host_callback_abi.zig src/build/codegen_context.zig src/build/codegen_host_imports.zig src/build/codegen_emit_expression.zig src/build/codegen_pipeline.zig src/build/host_export_manifest.zig src/build/test/compile_ok/343_host_static_callback.do src/build/test/compile_ok/343_host_static_callback.expect src/build/test/compile_ok/343_host_static_callback.host_manifest.expect
git commit -m "feat: lower host callbacks as static ids"
```

## Task 5: Implement Subscription And Instance Disposal In The Browser Adapter

**Files:**
- Create: `examples/ui-signal/host-runtime.ts`
- Create: `examples/ui-signal/host-runtime.test.ts`
- Modify: `examples/ui-signal/demo.ts`
- Modify: `examples/ui-signal/package.json`
- Modify: `examples/ui-signal/README.md`

**Interfaces:**
- Produces: `instantiateDo(wasm, manifest): Promise<DoHostInstance>`.
- Produces: `DoHostInstance.dispose(): void` and `DoHostInstance.unsubscribe(id: number): void`.
- Consumes: `static-id` callback manifest entries and Task 3 value converters.

- [ ] **Step 1: Write adapter lifecycle tests first**

```ts
it("removes a listener before invalidating its callback id", () => { /* ... */ });
it("does not dispatch after unsubscribe", () => { /* ... */ });
it("does not dispatch after instance.dispose", () => { /* ... */ });
it("releases copied text when callback dispatch throws", () => { /* ... */ });
```

Use a fake event target and fake Wasm exports so each assertion observes listener removal and dispatcher status handling.

- [ ] **Step 2: Run tests to verify the adapter does not exist**

Run: `cd examples/ui-signal && bun test host-runtime.test.ts`

Expected: FAIL because `host-runtime.ts` is absent.

- [ ] **Step 3: Implement the adapter registry**

Store subscriptions as `{ target, event, listener, callbackId }`. `unsubscribe` must remove the listener before deleting its entry. `dispose` must unsubscribe every entry, mark the instance disposed, and reject later dispatches. A callback id is valid only while this adapter owns a live instance.

- [ ] **Step 4: Wire the real demo without removing the existing simulator**

Add an explicit demo entry that loads emitted WAT/Wasm plus manifest through `instantiateDo`. Keep current signal-runtime examples as separate tests so this change proves the host boundary rather than rewriting unrelated UI behavior.

- [ ] **Step 5: Verify adapter, build, and browser smoke**

Run: `cd examples/ui-signal && bun run verify && bun run build`

Run: `cd ../.. && ./src/build/test/run_tests.sh && git diff --check`

Expected: all TypeScript checks pass; compiler suite passes; browser smoke shows callback dispatch before unsubscribe and none after dispose.

- [ ] **Step 6: Commit**

```bash
git add examples/ui-signal/host-runtime.ts examples/ui-signal/host-runtime.test.ts examples/ui-signal/demo.ts examples/ui-signal/package.json examples/ui-signal/README.md
git commit -m "feat: add lifecycle-safe browser host adapter"
```

## Task 6: Align The Existing WIT/Component Pipeline Without Replacing The Core Path

**Files:**
- Modify: `doc/wit/wasi_p3_lowering.md`
- Modify: `doc/host-binding-design.md`
- Create: `src/build/test/compile_ok/344_host_subscription_component.do`
- Create: `src/build/test/compile_ok/344_host_subscription_component.component_plan.expect`
- Modify: `src/build/test/README.md`

**Interfaces:**
- Produces: a documented WIT mapping: subscription is `resource subscription`, callback delivery becomes future stream/poll work, and `static-id` remains an internal Core adapter detail.
- Produces: a component-plan rejection for callback imports until the future/stream lowering exists; no misleading partial component output.

- [ ] **Step 1: Add a failing component-plan fixture**

Create a fixture with a registered subscription host import and a `.component_plan.expect` requiring the exact rejection `HostCallbackComponentAsyncUnsupported` until stream/future lowering is implemented.

- [ ] **Step 2: Run the component gate**

Run: `./src/build/test/run_tests.sh`

Expected: fixture is either absent from the component-plan gate or fails without the named diagnostic.

- [ ] **Step 3: Document the non-leaky Component mapping**

Add: `Subscription -> resource subscription`, Do `unsubscribe -> resource destructor/close`, copied event data -> WIT record/list/string, and future event delivery -> WIT stream/future. State that callback ids are never emitted into WIT and are only used by the temporary Core JS adapter.

- [ ] **Step 4: Add the explicit component-plan guard**

Detect static-id callback imports in the component-plan builder and fail with `HostCallbackComponentAsyncUnsupported`. This preserves correctness until the async Component Model implementation can produce stream/future lowering.

- [ ] **Step 5: Verify component and full gates**

Run: `./src/build/test/run_tests.sh`

Expected: `344_*` proves rejection is deliberate; existing `wasm-tools component embed/new/validate` gates remain green where installed.

- [ ] **Step 6: Commit**

```bash
git add doc/wit/wasi_p3_lowering.md doc/host-binding-design.md src/build/test/compile_ok/344_host_subscription_component.do src/build/test/compile_ok/344_host_subscription_component.component_plan.expect src/build/test/README.md
git commit -m "docs: align host callbacks with component resources"
```

## Final Verification

- [ ] Run `cd src && zig build -Doptimize=ReleaseSmall`.
- [ ] Run `./src/build/test/run_tests.sh` and record its final summary.
- [ ] Run `cd examples/ui-signal && bun run verify && bun run build`.
- [ ] Run the browser adapter smoke test with the real generated manifest.
- [ ] Run `git diff --check`.
- [ ] Update `doc/host_abi_blockers.md` to mark only independently verified work as resolved.
- [ ] Commit the final documentation/status update separately.
