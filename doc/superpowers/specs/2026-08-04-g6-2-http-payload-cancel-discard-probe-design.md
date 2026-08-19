# G6.2 HTTP Payload Cancellation Discard Probe Design

**Status:** Verified. The probe established the string destruction protocol;
the follow-on bounded compiler lowering is covered by the generated
Component/Rust gate.

## Decision

Establish the destruction protocol for one immediate, payload-bearing HTTP
completion before changing the compiler's cancellation template. The probe is
limited to the pinned `DNS-error` variant returned by `wasi:http/client.send`:

```wit
dns-error(dns-error-payload {
    rcode: option<string>,
    info-code: option<u16>,
})
```

The host returns `DnsError({ rcode: Some("EAI"), info-code: Some(7) })`
immediately. The Core module must verify that canonical lowering allocates the
`"EAI"` string through its exported `cabi_realloc`, then discard the payload by
calling `cabi_realloc(pointer, length, 1, 0)` exactly once. A normal return is
valid only after the probe's allocator has validated one allocation and one
matching release. Any omitted release, duplicate release, unexpected allocation,
or wrong reallocation arguments traps.

## Boundary

This is an ABI experiment, not a source-language feature. It does not add
`Some`/`None`, public ownership/reference types, implicit cancellation, generic
payload destruction, or a general allocator to Do.

During the probe, the existing compiler-generated cancellation fixture remained
unchanged and trapped for immediate `DNS-error`. The follow-on lowering now
consumes the proven protocol for `DNS-error.rcode` as either `None` or a
nonempty `Some`, and for `InternalError` as either `None` or a nonempty `Some`;
`None` does not read pointer/length fields. Broader boundaries remain rejected.

## Pinned Memory Contract

The existing private cancellation template passes result area `[64, 128)` to
`[async-lower]send`. The registered `DNS-error` layout is:

| Result-area offset | Meaning |
| --- | --- |
| `0` | `result` discriminant: `1` for `Err` |
| `8` | `error-code` discriminant: `1` for `DNS-error` |
| `16` | `rcode` option discriminant: `1` for `Some` |
| `20` | `rcode` UTF-8 data pointer |
| `24` | `rcode` byte length |
| `28` | `info-code` option discriminant |
| `30` | `info-code` value when present |

For `Some("EAI")`, the ABI call sequence must be exactly:

```text
cabi_realloc(0, 0, 1, 3) -> string_ptr
cabi_realloc(string_ptr, 3, 1, 0) -> ignored
```

The first call comes from Component canonical lowering. The second comes from
the Core guest after it has read and discarded the `DNS-error` payload. The
probe owns neither a response nor a subtask in this immediate-completion branch.

## Probe Shape

1. Add an isolated hand-authored Core WAT module using the same private
   `http-payload-cancel` service world as the compiler fixture.
2. Its `cabi_realloc` acts as a single-allocation verifier rather than a general
   allocator. It grants only the expected allocation, remembers its pointer,
   accepts only the matching free, and traps on every other call.
3. After `[async-lower]send` returns `Status::Returned`, the WAT validates the
   `Err`/`DNS-error`/`Some` discriminants and the `info-code`, reads `"EAI"`,
   calls the verified free, then asserts allocation count = release count = 1.
4. Reuse the Rust host fixture in an explicit `--expect-dns-error-discard` mode.
   It must see one consumed request, a ready future poll/drop of `1/1`, no
   response allocation/drop, and an empty host resource table.

## Acceptance and Stop Conditions

The probe was accepted when its Component assembly and Rust/Wasmtime run
returned normally for `ready-dns-error`, while the then-existing generated
cancellation gate still trapped for that mode. The follow-on generated gate now
returns normally for bounded DNS and InternalError string cases and retains
explicit traps for unsupported option/variant shapes.

Keep the explicit trap for unsupported shapes and record the blocker if any of
these occurs:

- the host does not call `cabi_realloc` with the expected allocation;
- the data bytes or canonical offsets differ;
- the Core module cannot prove one matching free;
- the Component runtime performs an additional or conflicting release;
- the existing pending, `Ok(response)`, or `DnsTimeout` cancellation behavior
  regresses.

## Verification

```bash
TMPDIR="$PWD/.tmp/do-tmp" \
  bash examples/p3-runtime/test_rust_http_payload_cancellation_dns_error_probe.sh
TMPDIR="$PWD/.tmp/do-tmp" \
  bash examples/p3-runtime/test_rust_http_payload_cancellation.sh
cd src && zig test build/codegen_component_wasi_http.zig
git diff --check
```
