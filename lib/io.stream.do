// Declarative stream hosts first (import prefix), then resource shells.
// Fallible hosts use exclusive Ok|Err unions (err arm = status i32).
.host_input_read = @wasi_func("io/streams/input-stream.read", (InputStream, u64) -> [u8] | i32)
.host_output_check_write = @wasi_func("io/streams/output-stream.check-write", (OutputStream) -> u64 | i32)
.host_output_write = @wasi_func("io/streams/output-stream.write", (OutputStream, [u8]) -> nil | i32)
.host_output_flush = @wasi_func("io/streams/output-stream.flush", (OutputStream) -> nil | i32)

InputStream = @wasi_resource("io/streams/input-stream", {
    .id i64
})

OutputStream = @wasi_resource("io/streams/output-stream", {
    .id i64
})

// WIT stream-error 当前只对应 closed；其余分支是 wrapper-local 故障分类。
StreamError error = StreamClosed | StreamReadFailed | StreamCheckWriteFailed | StreamWriteFailed | StreamFlushFailed

.stream_id(stream InputStream) -> i64 {
    return @get(stream, .id)
}

.output_stream_id(stream OutputStream) -> i64 {
    return @get(stream, .id)
}

// status from nil|i32 / u64|i32 err arm is error-code+1 (never 0); 1 => closed.
.stream_status_to_error(code i32, fallback StreamError) -> StreamError | nil {
    if @eq(code, 0) return nil
    if @eq(code, 1) return StreamClosed
    return fallback
}

// Host is [u8]|i32; bind exclusive union then map err status (no multi-lhs).
read_stream(stream InputStream, size usize) -> [u8], StreamError | nil {
    r [u8] | i32 = host_input_read(stream, @as(u64, size))
    if @is(r, i32) {
        empty [u8] = .{}
        return empty, stream_status_to_error(r, StreamReadFailed)
    }
    return r, nil
}

check_write_stream(stream OutputStream) -> u64, StreamError | nil {
    n u64 | i32 = host_output_check_write(stream)
    if @is(n, u64) return n, nil
    return 0, stream_status_to_error(n, StreamCheckWriteFailed)
}

write_stream(stream OutputStream, data [u8]) -> StreamError | nil {
    s nil | i32 = host_output_write(stream, data)
    if @eq(s, nil) return nil
    return stream_status_to_error(s, StreamWriteFailed)
}

flush_stream(stream OutputStream) -> StreamError | nil {
    s nil | i32 = host_output_flush(stream)
    if @eq(s, nil) return nil
    return stream_status_to_error(s, StreamFlushFailed)
}

is_stream_closed(err StreamError) -> bool {
    return @eq(err, StreamClosed)
}
