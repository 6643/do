# HTTP Request Body Stream Design

## Goal

Extend the pinned `wasi:http@0.3.0-rc-2025-09-16` request-construction probe
with one bounded non-empty `stream<u8>` body path. The path must construct a
request, transfer it once to the existing `client.send` probe, and dispose the
body reader, body completion future, request transmission future, and request
or response resources exactly once.

## Source Boundary

Do source continues to hide WIT `own<T>` and `borrow<T>`. The admitted source
shape is a compiler-recognized `@host` declaration for `request.new` whose
single source parameter is `Stream<u8>` and whose result remains
`Tuple<HttpRequest, Future<Result<nil, HttpError>>>`. The body reader comes from
the pinned `wasi:cli/stdin.read-via-stream` descriptor. The fixture's Rust host
supplies exactly two bytes (`65`, `66`), so the runtime proof is finite without
introducing loops or a source-level producer API.

The compiler accepts only this fixed sequence:

1. acquire the body reader and its independent completion future;
2. call `request.new(body_reader)` with empty fields, `Ok(None)` trailers, and
   no request options;
3. transfer the returned request once to `client.send`;
4. await the existing HTTP result; and
5. cancel or consume the body completion future before terminal cleanup.

Dynamic stream loops, arbitrary stream sources, body writes from Do source,
multiple requests, trailer payload inspection, and payload-bearing HTTP
`error-code` variants remain rejected.

## ABI And Ownership

The request constructor uses the pinned seven-word canonical call. Its body
stream is passed as the reader half of the `stream-new` pair. The body source
completion future is independent from the request transmission future; neither
may be silently dropped. A body reader is dropped only after `client.send` has
reached a terminal state. External effects are not rolled back on cancellation.

The combined path is assembled with the complete pinned WIT package emitted by
`--p3-wit-package-output`. A shortened standalone sidecar is not authoritative
because its reduced `error-code` shape cannot represent the pinned task-return
ABI.

## Verification

The implementation must provide:

- a Core WAT assertion for body stream imports and the seven-word `request.new`;
- Component assembly and `wasm-tools validate` success;
- a Rust/Wasmtime runner that executes two calls in one Store, observes body
  bytes `[65,66]`, both success and no-payload `DNS-timeout`, and an empty
  `ResourceTable`; and
- focused Zig tests, the repository regression suite, and `git diff --check`.
