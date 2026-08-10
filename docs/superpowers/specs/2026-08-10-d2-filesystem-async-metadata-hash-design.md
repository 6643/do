# D2 `descriptor.metadata-hash` Async Filesystem Design

Date: 2026-08-10
Status: private method-specific slice verified; generic filesystem async remains blocked

## Goal

Measure and, only after all current-only ABI and cleanup gates pass, privately
promote one bounded WASI filesystem async method:

```wit
descriptor.metadata-hash: async func() -> result<metadata-hash-value, error-code>
```

The method observes metadata and has no guest-visible mutation to roll back.
Cancellation follows the Component/WASI contract: it ends live Component state
and releases still-owned guest values, but does not fabricate rollback of host
work that has already been issued.

## Decision

Keep this as a separate `filesystem-metadata-hash` capability. Do not reuse the
`descriptor.stat`, scalar Result, or generic filesystem async emitters. Do
not add public Do `Result<T,E>`, `own<T>`, `borrow<T>`, `ref<T>`, pointer,
reference, lifetime, or generic async syntax.

The candidate is intentionally narrower than `metadata-hash-at`: it has no
path-flags or string argument ownership. `metadata-hash-at` remains pending
until it has its own mixed enum/string ABI and cleanup matrix.

## Pinned Inputs

- Upstream source:
  `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit`
- Upstream source SHA-256:
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`
- WASI package/version: `wasi:filesystem@0.3.0-rc-2025-09-16`
- Method locator: `wasi:filesystem/types@0.3.0-rc-2025-09-16`
- Current tool: `wasm-tools 1.255.0 (76e20611d 2026-07-30)`
- Current tool SHA-256:
  `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`
- Rust: `rustc 1.97.1 (8bab26f4f 2026-07-14)`
- Wasmtime: `47.0.2`
- Component features: `cm-async,cm-more-async-builtins`

The upstream source and tool hashes are identity gates. A hand-authored WIT
mirror must have its own recorded hash and cannot replace the upstream hash.

## WIT Shape

The probe must preserve the exact upstream record order and error-code order:

```wit
record metadata-hash-value {
    lower: u64,
    upper: u64,
}

descriptor.metadata-hash: async func() -> result<metadata-hash-value, error-code>
```

The probe world imports only `types`, exports a `probe` interface, and exposes:

```wit
run: async func(file: own<descriptor>) -> result<metadata-hash-value, error-code>
```

A cancel-only world adds `cancel: async func()` and does not add another
filesystem method.

## Measured ABI Candidate

The current `wasm-tools 1.255.0` dummy embed probe already measures these
method-specific widths:

```text
[async-lower][method]descriptor.metadata-hash: (i32, i32) -> i32
[resource-drop]descriptor: (i32) -> nil
[task-return]run: (i32, i64, i64)
```

The committed ABI gate must independently verify the complete WIT mirror,
method count, Core types, component validation, and generated Component WIT.
It must also verify the result-area layout rather than infer it from the
neighboring `stat` slice. The expected candidate layout is:

```text
frame+8:  result tag (u8)
frame+16: lower (u64) on Ok, error-code payload on Err
frame+24: upper (u64) on Ok
```

The gate must fail closed if the tag width, payload offset, flat completion
order, or error payload differs. The hand-authored Core template must use a
fixed frame and explicit markers for call, result area, ready, pending, error,
descriptor drop, and cancellation.

## Private Do Admission

Only this exact source shape may be admitted after the ABI/runtime gates pass:

```do
metadata_hash = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.metadata-hash", (Dir) -> MetadataHash | HashError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
MetadataHash = @wasi_record("filesystem/types/metadata-hash-value", { lower u64, upper u64 })
HashError error = Io | NoEntry

run(file Dir) -> MetadataHash | HashError {
    pending Future<MetadataHash | HashError> = metadata_hash(file)
    return @await(pending)
}

start() {}
```

The default compiler path must continue to reject this source before WAT. The
opt-in component target may admit only one exact host binding, one matching
resource declaration, one direct await, one ordinary `run` root, and an empty
`start`. It must reject an unregistered member, wrong record field order/type,
borrowed payload, a second await, branches/loops/defer, an async root, extra
host bindings, `metadata-hash-at`, and public `Result<T,E>` spelling.

## Runtime Oracle

The Rust/Wasmtime runner must use a new Component/Store for each mode and
report the following rows:

| Mode | Host behavior | Required observation |
| --- | --- | --- |
| ready | immediate hash | exact lower/upper values, one completion, one future drop, one descriptor drop |
| pending | one pending poll then external wake | one wake and one completion with both `u64` words intact |
| error | closed or invalid descriptor | `Err(no-entry)`, no fabricated hash payload |
| cancel | pending future followed by test-only subtask cancel | no business completion, one pending-future drop, one descriptor drop |
| early-drop | abandon call, dispose the whole Store | one pending-future drop; `table-empty=not-applicable` |
| repeat | two sequential calls with different known hashes | independent results, no stale upper/lower words, exactly-once cleanup |

Cancellation is cleanup only. No row may claim that metadata observed or work
issued at the host was rolled back.

## Promotion Evidence

The complete method-specific gate is green with the pinned current toolchain:

- `bash examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_abi.sh` passes
  with upstream WIT hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`,
  regular/cancel mirror hashes
  `6976359b3a4813d6771b3ef9a7fdcfb2ee9323e70c33b9ac7d6b628519fecfed` /
  `b6e98cf2ae6f76e105f53c7ea09666b1c5684d33edb9838d034862a27b09f5c3`, and
  `wasm-tools 1.255.0` SHA-256
  `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
- `bash examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash.sh` passes
  ready/pending/error/repeat; cancel and Store-disposal early-drop remain the
  hand-authored oracle rows, with cleanup-only cancellation semantics.
- The opt-in `--p3-async-component` compiler admits fixture `516`, rejects
  `517`-`519` before WAT, and the Core template hash is
  `f51c82887174a7ed1adf95a1cbe0e333f80a487962a2a8478334ca9750933b6b`.
- `zig test src/build/p3_async_manifest.zig` passes `97/97`,
  `zig test src/build/sema_imports.zig` passes `163/163`,
  `(cd src && zig test build/codegen_component_async.zig)` passes `502/502`,
  `(cd src && zig test main.zig)` passes `347/347`,
  `./src/build/test/run_tests.sh` passes `pass=1199 fail=0 skip=3`, and the
  `RUN_WASM=1 SKIP_BUILD=1` rerun passes `pass=1201 fail=0 skip=3` with WASM
  smoke `6/6`; `cd src && zig build -Doptimize=ReleaseSmall` exits `0`.

## No-Go Boundary

Outside this completed method-specific slice, keep these rejected:

- generic filesystem async lowering or arbitrary `@host_async_func` methods;
- `metadata-hash-at`, string/path ownership, or borrowed descriptor arguments;
- arbitrary producer expressions, resource/list/stream futures, or borrowed
  async values;
- public ownership, pointer, reference, lifetime, or generic async syntax.

## Acceptance

Promotion requires all of the following for this exact method:

1. pinned regular/cancel WIT and Core ABI scripts pass with current tools;
2. hand-authored Rust/Wasmtime ready/pending/error/cancel/early-drop/repeat
   cleanup rows pass;
3. compiler registry, planner, emitter, one positive fixture, and fail-closed
   negative fixtures pass under the opt-in target;
4. generated Component WIT/WAT matches the pinned method and the runtime oracle;
5. full Zig, default/WASM, ReleaseSmall, documentation, and delivery gates pass.

If any gate fails, keep the probe/design as evidence and do not widen the
compiler.
