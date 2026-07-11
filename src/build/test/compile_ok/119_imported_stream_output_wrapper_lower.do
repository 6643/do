OutputStream = @lib("io.stream.do", OutputStream)
StreamError = @lib("io.stream.do", StreamError)
check_write_stream = @lib("io.stream.do", check_write_stream)
write_stream = @lib("io.stream.do", write_stream)
flush_stream = @lib("io.stream.do", flush_stream)

check_sample(stream OutputStream) -> u64, StreamError | nil {
    return check_write_stream(stream)
}

write_sample(stream OutputStream, data [u8]) -> StreamError | nil {
    return write_stream(stream, data)
}

flush_sample(stream OutputStream) -> StreamError | nil {
    return flush_stream(stream)
}

start() {
    return
}
