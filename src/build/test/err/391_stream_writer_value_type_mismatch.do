StreamError error = StreamClosed | StreamWriteFailed

produce() -> nil {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<nil, StreamError>> = writer(true)
    replied Result<nil, StreamError> = @await(pending)
    _ = replied
    defer close(writer)
    _ = reader
}

start() {}
