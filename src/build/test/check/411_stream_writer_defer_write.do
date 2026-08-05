StreamError error = StreamClosed | StreamWriteFailed

async produce() -> nil {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    defer close(writer)
    pending Future<Result<nil, StreamError>> = writer(65)
    replied Result<nil, StreamError> = await(pending)
    _ = replied
    _ = reader
}

test "deferred close keeps writer usable until scope exit" {}
