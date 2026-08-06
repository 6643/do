StreamError error = StreamClosed | StreamWriteFailed

produce() -> nil {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<u8, StreamError>> = writer(65)
    replied Result<u8, StreamError> = @await(pending)
    _ = replied
    defer close(writer)
    _ = reader
}

start() {}
