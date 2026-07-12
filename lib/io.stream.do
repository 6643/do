// Declarative stream hosts first (import prefix), then resource shells.
.host_input_read = @wasi_func("io/streams/input-stream.read", (i32, u64) -> result<[u8],stream-error>)
.host_output_check_write = @wasi_func("io/streams/output-stream.check-write", (i32) -> result<u64,stream-error>)
.host_output_write = @wasi_func("io/streams/output-stream.write", (i32, [u8]) -> result<_,stream-error>)
.host_output_flush = @wasi_func("io/streams/output-stream.flush", (i32) -> result<_,stream-error>)

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

.stream_status_to_error(code i32, fallback StreamError) -> StreamError | nil {
    if @eq(code, 0) return nil
    if @eq(code, 1) return StreamClosed
    return fallback
}

read_stream(stream InputStream, size usize) -> [u8], StreamError | nil {
    data [u8] = .{}
    status i32 = 0
    data, status = host_input_read(@as(i32, stream_id(stream)), @as(u64, size))
    return data, stream_status_to_error(status, StreamReadFailed)
}

check_write_stream(stream OutputStream) -> u64, StreamError | nil {
    allowed u64 = 0
    status i32 = 0
    allowed, status = host_output_check_write(@as(i32, output_stream_id(stream)))
    return allowed, stream_status_to_error(status, StreamCheckWriteFailed)
}

write_stream(stream OutputStream, data [u8]) -> StreamError | nil {
    status i32 = 0
    _, status = host_output_write(@as(i32, output_stream_id(stream)), data)
    return stream_status_to_error(status, StreamWriteFailed)
}

flush_stream(stream OutputStream) -> StreamError | nil {
    status i32 = 0
    _, status = host_output_flush(@as(i32, output_stream_id(stream)))
    return stream_status_to_error(status, StreamFlushFailed)
}

is_stream_closed(err StreamError) -> bool {
    return @eq(err, StreamClosed)
}
