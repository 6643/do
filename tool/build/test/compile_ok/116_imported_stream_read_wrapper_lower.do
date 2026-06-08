InputStream = @lib("io.stream.do", InputStream)
StreamOutcome = @lib("io.stream.do", StreamOutcome)
read_stream = @lib("io.stream.do", read_stream)

read_sample(stream InputStream) -> [u8], StreamOutcome {
    return read_stream(stream, 16)
}

start() {
    return
}
