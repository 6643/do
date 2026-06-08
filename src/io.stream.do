StreamError error = StreamClosed | StreamReadFailed | StreamWriteFailed | StreamFlushFailed
StreamOutcome = StreamError | nil

.host_input_read = @wasi("io/streams/input-stream.read", (input-stream, u64) -> result<list<u8>,stream-error>)
.host_output_check_write = @wasi("io/streams/output-stream.check-write", (output-stream) -> result<u64,stream-error>)
.host_output_write = @wasi("io/streams/output-stream.write", (output-stream, list<u8>) -> result<_,stream-error>)
.host_output_flush = @wasi("io/streams/output-stream.flush", (output-stream) -> result<_,stream-error>)

InputStream {
    .id i64
}

OutputStream {
    .id i64
}

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

read_stream(stream InputStream, size usize) -> [u8], StreamOutcome {
    data [u8] = .{}
    status i32 = 0
    data, status = host_input_read(@to_i32(stream_id(stream)), @to_u64(size))
    return data, stream_status_to_error(status, StreamReadFailed)
}

check_write_stream(stream OutputStream) -> u64, StreamOutcome {
    allowed u64 = 0
    status i32 = 0
    allowed, status = host_output_check_write(@to_i32(output_stream_id(stream)))
    return allowed, stream_status_to_error(status, StreamWriteFailed)
}

write_stream(stream OutputStream, data [u8]) -> StreamOutcome {
    status i32 = 0
    _, status = host_output_write(@to_i32(output_stream_id(stream)), data)
    return stream_status_to_error(status, StreamWriteFailed)
}

flush_stream(stream OutputStream) -> StreamOutcome {
    status i32 = 0
    _, status = host_output_flush(@to_i32(output_stream_id(stream)))
    return stream_status_to_error(status, StreamFlushFailed)
}

is_stream_closed(err StreamError) -> bool {
    return @eq(err, StreamClosed)
}
