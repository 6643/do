request_new = @host("wasi:http/types@0.3.0-rc-2025-09-16", "request.new", (Stream<u8>) -> Tuple<HttpRequest, Future<Result<nil, HttpError>>>)
stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)

HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
HttpRequest = @wasi_resource("http/types/request", { .id i64 })
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
StdoutError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed
HttpError error = HttpFailure

run() -> Result<HttpResponse, HttpError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    first u8 = 65
    write_pending Future<Result<nil, StreamError>> = writer(first)
    write_result Result<nil, StreamError> = @await(write_pending)
    _ = write_result
    second u8 = 66
    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
    write_result_2 Result<nil, StreamError> = @await(write_pending_2)
    _ = write_result_2
    close(writer)
    handles Tuple<HttpRequest, Future<Result<nil, HttpError>>> = request_new(reader)
    request HttpRequest = @get(handles, 0)
    pending Future<Result<HttpResponse, HttpError>> = send(request)
    result Result<HttpResponse, HttpError> = @await(pending)
    return result
}

start() {}
