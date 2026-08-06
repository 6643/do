StreamError error = StreamClosed | StreamWriteFailed

produce(stop bool, writer StreamWriter<i32>) -> nil {
    if stop {
        close(writer)
    }
    pending Future<Result<nil, StreamError>> = writer(65)
    replied Result<nil, StreamError> = @await(pending)
    _ = replied
}

test "a maybe writer cannot be used after a conflicting join" {}
