# Task 1: G6.2 Scalar-List Producer Baseline

Date: 2026-08-09
Status: DONE

## Checkout and pinned tools

Commands:

```text
git status --short --branch
git rev-parse main origin/main
zig version
wasm-tools --version
rustc --version
wasmtime --version
```

Results:

```text
## g6-2-scalar-list-producer-promotion
e106e0f3ca4e34f35b31d38523d3500b0f2fd21f
a98b4be84b07dda462966b9464a4c5da238092b1
0.16.0
wasm-tools 1.255.0 (76e20611d 2026-07-30)
rustc 1.97.1 (8bab26f4f 2026-07-14)
wasmtime 47.0.2 (90fed3c6a 2026-07-21)
```

The promotion branch was clean at `e106e0f3ca4e34f35b31d38523d3500b0f2fd21f`.
`origin/main` was `a98b4be84b07dda462966b9464a4c5da238092b1`; the expected
tool versions were present.

## Evidence-only gate

Commands:

```bash
wasm-tools component wit examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
sha256sum examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
WASM_TOOLS_EXPECT_VERSION=1.255.0 bash examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh
```

The WIT command reproduced the expected `do:g6-2-scalar-list-producer@0.1.0`
package, `consume-via-stream: async func(data: stream<list<u32>>)` and
`produce: async func(count: u32)` definitions.

The WIT hash was unchanged:

```text
a24e467b1746f94432bb495c13fc0ce718a3833dc0ce7659228cfb6eaf69ff9f  examples/p3-runtime/wit/g6-2-scalar-list-producer.wit
```

The ABI probe passed and produced all ten machine-checkable rows:

```text
mode=count-0 result=Some((Ok(()),)) values=[] expected=[] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=count-1 result=Some((Ok(()),)) values=[10] expected=[10] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=count-2 result=Some((Ok(()),)) values=[10, 20] expected=[10, 20] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=count-3 result=Some((Ok(()),)) values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=pending result=Some((Ok(()),)) values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=1 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=sink-error result=Some((Err(Pipe),)) values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=early-drop result=Some((Err(Pipe),)) values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=cancel-before-transfer result=Some((Ok(()),)) values=[] expected=[] host-calls=1 pending-polls=0 stream-drops=0 cancel-calls=0 list-releases=1 table-empty=true
mode=cancel-after-transfer result=None values=[10, 20, 30] expected=[10, 20, 30] host-calls=1 pending-polls=0 stream-drops=1 cancel-calls=0 list-releases=1 table-empty=true
mode=count-4 result=Some((Err(InvalidMode),)) values=[] expected=[] host-calls=0 pending-polls=0 stream-drops=0 cancel-calls=0 list-releases=0 table-empty=true
G6.2 scalar list producer canonical ABI probe passed
```

This confirms one list release and an empty resource table for each admitted
terminal row; `count-4` performs no host call and no release.

## Boundary checks

```bash
git diff --check
git diff -- src/build/p3_async_manifest.zig src/build/p3_async_registry.json src/build/sema_imports.zig
```

Both checks were clean. No compiler admission, registry row, sema, codegen, or
public syntax changes were made. No dated baseline note was needed because the
pinned versions and WIT hash matched the brief.

## Concerns

None observed in this baseline run. The probe is evidence-only; compiler
promotion remains outside Task 1.
