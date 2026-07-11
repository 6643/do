InputStream = @lib("io.stream.do", InputStream)
StreamError = @lib("io.stream.do", StreamError)
read_stream = @lib("io.stream.do", read_stream)

read_sample(stream InputStream) -> [u8], StreamError | nil {
    return read_stream(stream, 16)
}

start() {
    return
}
