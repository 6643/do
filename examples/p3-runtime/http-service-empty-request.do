request_new = @host("wasi:http/types@0.3.0-rc-2025-09-16", "request.new", () -> Tuple<HttpRequest, Future<Result<nil, HttpError>>>)
send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)

HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
HttpRequest = @wasi_resource("http/types/request", { .id i64 })
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
HttpError error = HttpFailure

run() -> Result<HttpResponse, HttpError> {
    handles Tuple<HttpRequest, Future<Result<nil, HttpError>>> = request_new()
    request HttpRequest = @get(handles, 0)
    pending Future<Result<HttpResponse, HttpError>> = send(request)
    return @await(pending)
}

start() {}
