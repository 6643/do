// Declarative stream hosts first (import prefix), then resource shells.
// Fallible hosts use exclusive Ok|Err with coarse StreamError (aligned with dir/file P4).
.host_input_read = @wasi_func("io/streams/input-stream.read", (InputStream, u64) -> [u8] | StreamError)
.host_output_check_write = @wasi_func("io/streams/output-stream.check-write", (OutputStream) -> u64 | StreamError)
.host_output_write = @wasi_func("io/streams/output-stream.write", (OutputStream, [u8]) -> StreamError | nil)
.host_output_flush = @wasi_func("io/streams/output-stream.flush", (OutputStream) -> StreamError | nil)

InputStream = @wasi_resource("io/streams/input-stream", {
    .id i64
})

OutputStream = @wasi_resource("io/streams/output-stream", {
    .id i64
})

// WIT stream-error closed maps to StreamClosed; other non-zero status → *Failed (codegen coarse map).
StreamError error = StreamClosed | StreamReadFailed | StreamCheckWriteFailed | StreamWriteFailed | StreamFlushFailed

.stream_id(stream InputStream) -> i64 {
    return @get(stream, .id)
}

.output_stream_id(stream OutputStream) -> i64 {
    return @get(stream, .id)
}

// Host is [u8]|StreamError; public multi-return keeps [u8], StreamError|nil.
read_stream(stream InputStream, size usize) -> [u8], StreamError | nil {
    r [u8] | StreamError = host_input_read(stream, @as(u64, size))
    if @is(r, StreamError) {
        empty [u8] = .{}
        return empty, r
    }
    return r, nil
}

check_write_stream(stream OutputStream) -> u64, StreamError | nil {
    n u64 | StreamError = host_output_check_write(stream)
    if @is(n, u64) return n, nil
    return 0, n
}

write_stream(stream OutputStream, data [u8]) -> StreamError | nil {
    return host_output_write(stream, data)
}

flush_stream(stream OutputStream) -> StreamError | nil {
    return host_output_flush(stream)
}

is_stream_closed(err StreamError) -> bool {
    return @eq(err, StreamClosed)
}
