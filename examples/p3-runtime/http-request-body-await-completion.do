stdin_read = @host_func("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
request_new = @host_func("wasi:http/types@0.3.0-rc-2025-09-16", "request.new", (Stream<u8>) -> Tuple<HttpRequest, Future<Result<nil, HttpError>>>)
send = @host_async_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)

HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
HttpRequest = @wasi_resource("http/types/request", { .id i64 })
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
StdinError error = Io | IllegalByteSequence | Pipe
HttpError error = HttpFailure

run() -> Result<HttpResponse, HttpError> {
    source Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
    reader Stream<u8> = @get(source, 0)
    source_done Future<Result<nil, StdinError>> = @get(source, 1)
    source_result Result<nil, StdinError> = @await(source_done)
    handles Tuple<HttpRequest, Future<Result<nil, HttpError>>> = request_new(reader)
    request HttpRequest = @get(handles, 0)
    pending Future<Result<HttpResponse, HttpError>> = send(request)
    result Result<HttpResponse, HttpError> = @await(pending)
    return result
}

start() {}
