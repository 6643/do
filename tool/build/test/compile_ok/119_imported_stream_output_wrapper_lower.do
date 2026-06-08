OutputStream = @lib("io.stream.do", OutputStream)
StreamOutcome = @lib("io.stream.do", StreamOutcome)
check_write_stream = @lib("io.stream.do", check_write_stream)
write_stream = @lib("io.stream.do", write_stream)
flush_stream = @lib("io.stream.do", flush_stream)

check_sample(stream OutputStream) -> u64, StreamOutcome {
    return check_write_stream(stream)
}

write_sample(stream OutputStream, data [u8]) -> StreamOutcome {
    return write_stream(stream, data)
}

flush_sample(stream OutputStream) -> StreamOutcome {
    return flush_stream(stream)
}

start() {
    return
}
