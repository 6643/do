# Generic Stream-Writer Producer Runtime Design

## Goal

Run the existing bounded guest `StreamWriter<u8>` producer pump through the
registered private `do:stream-probe@0.1.0` descriptor, proving that writer
lowering and lease cleanup are descriptor-driven rather than tied to the
pinned `wasi:cli/stdout` package.

## Admitted Shape

The Do source creates one capacity-one `StreamReader<u8>, StreamWriter<u8>`
pair, performs two literal `u8` writes with one await per write, closes the
writer exactly once, transfers the reader once to
`do:stream-probe@0.1.0/sink.write-via-stream`, and awaits the no-payload
completion result. The private WIT world exports `produce` and imports the
custom sink interface. The Rust host consumes the reader and records `[65,66]`.

The emitter, frame layout, backpressure behavior, and error mapping remain the
existing bounded `StreamWriter<u8>` implementation. This gate adds no public
ownership syntax, dynamic producer loop, arbitrary element type, or producer
error payload mapping.

## Cleanup Contract

The guest closes the writable endpoint once; the host consumer drops the reader
once; terminal completion drops the completion future and frame. Pending and
ready host callback modes, host `Err(pipe)`, and scheduler admission/rejection
must match the existing stdout producer evidence.

## Borrowed-Field Boundary

Borrowed resource record fields are not admitted by this gate. The pinned
`wasmparser 0.252.0` validator rejects any component function result whose
recursive type contains `borrow`; a record carrying `borrow<T>` as a stream
element would therefore be invalid as the returned stream/future tuple. Keep
the manifest rejection and do not synthesize a borrowed record ABI.
