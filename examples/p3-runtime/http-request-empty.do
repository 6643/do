request_new = @host("wasi:http/types@0.3.0-rc-2025-09-16", "request.new", () -> Tuple<HttpRequest, Future<Result<nil, HttpError>>>)

HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
HttpRequest = @wasi_resource("http/types/request", { .id i64 })
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
HttpError error = HttpFailure

async run() -> nil {
    handles Tuple<HttpRequest, Future<Result<nil, HttpError>>> = request_new()
    _ = handles
}

start() {}
