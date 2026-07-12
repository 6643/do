// C: stream read host Err arm is coarse StreamError (not status i32).
.host_input_read = @wasi_func("io/streams/input-stream.read", (InputStream, u64) -> [u8] | StreamError)
InputStream = @wasi_resource("io/streams/input-stream", { .id i64 })
StreamError error = StreamClosed | StreamReadFailed | StreamCheckWriteFailed | StreamWriteFailed | StreamFlushFailed

start() {
    s InputStream = InputStream{id = 1}
    r [u8] | StreamError = host_input_read(s, 64)
    _ = r
    return
}
