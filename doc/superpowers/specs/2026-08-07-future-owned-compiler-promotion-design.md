# G6.2.4 Private `future<own<T>>` Compiler Promotion Design

Status: approved route; design review required before implementation.

Date: 2026-08-07

## Decision

Promote exactly one measured owned-future shape into an opt-in compiler target:

```wit
resource ticket {}
read: func() -> future<own<ticket>>;
```

The Do source remains ownership-syntax-free. A private registry descriptor
maps the existing source spelling `Future<Ticket>` to the WIT spelling
`future<own<ticket>>`. This is a compiler/ABI promotion, not the introduction
of public `own<T>`, `borrow<T>`, or `ref<T>` types.

The target is invoked explicitly as:

```text
do build input.do --p3-owned-future-component --p3-wit-output output.wit -o output.wat
```

It is mutually exclusive with `--p3-async-component`,
`--p3-async-call-component`, `--p3-async-component-v2`, all other P3 special
targets, `--component-core`, and `--host-export`. Existing targets keep their
current dispatch and rejection behavior.

## Evidence Boundary

The promotion is based on the already verified private runtime probe:

- `wasm-tools 1.255.0 (76e20611d 2026-07-30)` for the capability and WIT
  shape;
- Wasmtime `47.0.2` through the existing Rust host runner;
- `examples/p3-runtime/future-owned-canonical.wat`;
- `examples/p3-runtime/wit/future-owned-canonical.wit`;
- `examples/p3-runtime/test_future_owned_canonical_abi.sh`;
- `examples/p3-runtime/rust-host-runner/src/bin/future_owned_canonical_abi.rs`.

The probe proves ready, pending-once, and root-cancel execution, exactly-once
future/resource cleanup, representation `0`, and an empty host `ResourceTable`.
It does not prove generic owned futures, borrowed futures, owned streams,
arbitrary resource payloads, or general producer composition.

## Source Contract

The positive fixture uses only existing Do constructs:

```do
read = @host("do:future-owned-canonical/source@0.1.0", "read", () -> Future<Ticket>)
Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })

run(mode u32) -> nil {
    pending Future<Ticket> = read()
    ticket Ticket = @await(pending)
}

start() {}
```

`run` is an ordinary Do function. The opt-in target turns the function that
contains `@await` into the single asynchronous WIT export. `mode` is a probe
control value retained in the private frame; it is not an ownership API.

The exact positive source shape is deliberately narrow:

- one `@host` binding with the registered locator/member;
- zero host parameters and source result `Future<Ticket>`;
- one exact `@wasi_resource` declaration for `Ticket`;
- one root function `run(mode u32) -> nil`;
- one future local and one `@await` consuming it;
- no helper function, branch, loop, `defer`, explicit `@cancel`, or second
  live future.

The `Ticket` local is released by the existing ownership/drop machinery when
the root scope terminates. The source never spells `own<ticket>`.

## Private Descriptor

Add one descriptor to `src/build/p3_async_registry.json` with a dedicated
effect, `future-owned-resource`, rather than overloading the existing scalar,
Result, or stream effects:

```json
{
  "locator": "do:future-owned-canonical/source@0.1.0",
  "member": "read",
  "effect": "future-owned-resource",
  "params": [],
  "result": "Ticket",
  "resource": null,
  "canonical": {
    "core_params": [],
    "core_results": [],
    "completion_params": [],
    "completion": "task-return",
    "async_import_module": "do:future-owned-canonical/source@0.1.0",
    "async_import_name": "[async-lower]read",
    "future_owned": {
      "resource": "ticket",
      "payload_offset": 12,
      "resource_offset": 16,
      "presence_offset": 20,
      "drop_import": "[resource-drop]ticket"
    }
  },
  "wit": {
    "package": "do:future-owned-canonical@0.1.0",
    "interface": "source",
    "operation": "read",
    "world": "future-owned-canonical",
    "parameter": ""
  }
}
```

The manifest parser gains a dedicated `FutureOwnedCanonical` record and a
`LoweringShape.future_owned_resource` branch. The validator requires every
field above, exact offsets, the exact async import name, and the exact WIT
identity. No descriptor with a different resource, offset, payload, or
completion shape is admitted by this target.

The offsets are private measured ABI facts, not source-visible layout
guarantees:

| Offset | Meaning | Cleanup rule |
| ---: | --- | --- |
| `+12` | canonical future payload destination | clear after transfer |
| `+16` | owned `ticket` representation | valid even when `0` |
| `+20` | independent presence bit | set only after successful creation |

## Lowering Architecture

Implement a separate analyzer/emitter pair, without routing through the v1
dispatcher, the bounded async-call emitter, or the Generic ABI v2 profile:

- `src/build/codegen_component_future_owned_plan.zig` performs exact source,
  descriptor, resource, and control-flow admission;
- `src/build/codegen_component_future_owned.zig` emits the private WAT and WIT
  shape from the plan;
- `src/build/codegen_pipeline.zig` dispatches the new option before the other
  async profiles and exposes only the new target's WIT emitter;
- `src/build/run.zig` writes the generated sidecar for the new target;
- `src/build/cli.zig` and `src/main.zig` expose and isolate the flag.

The emitter may reuse pure ABI/layout helpers and existing ARC release
helpers, but it must not broaden those helpers' public source admission. The
generated module has one exported asynchronous root and one internal frame;
it has no independent helper Component task endpoint.

The generated lifecycle is:

```text
root start
  -> call source.read
  -> store readable future and await frame
  -> ready: decode payload at +12, move representation to +16,
            set +20, clear +12, release future and ticket exactly once
  -> pending: join/wake and resume the same frame
  -> root cancellation: finish/cancel readable future, do not set +20,
                        release frame and return through the root terminal
```

The independent presence bit is mandatory because the host resource table can
assign representation `0`. Terminal cleanup checks and clears `+20` before
calling `[resource-drop]ticket`; a cancellation before resource creation must
not call the resource drop import.

## WIT Output

The sidecar emitted by the target must byte-match the pinned snapshot:

```wit
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
```

The `own<ticket>` spelling is confined to generated WIT and the private ABI
descriptor. It is not accepted by the Do lexer, parser, semantic checker, or
ordinary compiler target.

## Rejection Boundary

The new analyzer fails before WAT emission with one stable target-specific
diagnostic for each of these classes:

- missing or different descriptor locator/member/effect;
- `Future<T>` where `T` is not the exact registered `Ticket` resource;
- missing, duplicate, or different `@wasi_resource` declaration;
- host parameters, non-`Future<Ticket>` host result, or a second host binding;
- more than one future local, more than one await, explicit cancel, or a
  second live operation;
- helper functions, function values, recursion, branch/loop/defer, stream,
  list, variant, Result, borrowed value, or any nested resource payload;
- a source function declared with `async` rather than the ordinary
  colorless function shape;
- use through any other compiler target or missing `--p3-wit-output`.

Negative fixtures remain in a dedicated `compile_err`/focused gate set. They
must also assert that v1 and v2 targets do not accidentally accept the same
source.

## Runtime Gate

Add a compiler-generated gate beside the existing canonical probe. It must:

1. compile the positive Do fixture with `--p3-owned-future-component`;
2. compare generated WIT with the pinned snapshot;
3. parse the WAT with the pinned `wasm-tools 1.255.0` and assemble/validate the
   Component with the existing P3 legacy helper where required by the pinned
   async metadata;
4. run the existing Rust/Wasmtime host runner in `ready`, `pending`, and
   `cancel` modes;
5. assert one source host call, one future drop, one resource create/drop on
   ready and pending, no resource create/drop on cancel, exactly-once terminal
   cleanup, and `table-empty=true`;
6. assert that a host representation of `0` is accepted and dropped once;
7. assert target isolation and every negative diagnostic before WAT output.

The runtime gate does not add `stream<own<T>>`, `future<borrow<T>>`, a generic
`Future<T>` lowering rule, or filesystem/D2 host I/O.

## Documentation and Release Boundary

Update `doc/pending_blocked.md`, `doc/host_abi_blockers.md`,
`doc/roadmap_status.md`, and the relevant v1 plan only after the focused gate
is green. The status must distinguish:

- WIT/toolchain acceptance;
- private compiler promotion of one owned future;
- still-pending generic producer expressions, owned streams, borrowed async
  values, and D2 filesystem/network async.

The promotion is complete only when the manifest, CLI, analyzer, emitter,
positive WIT/Component gate, Rust/Wasmtime matrix, negative fixtures, and
documentation all pass. No public ownership syntax is a completion criterion.
