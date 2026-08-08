send = @host_async_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)

HttpRequest = @wasi_resource("http/types/request", { .id i64 })
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
HttpError error = HttpFailure

run(request HttpRequest) -> nil {
    first Future<Result<HttpResponse, HttpError>> = send(request)
    @await(first)
    second Future<Result<HttpResponse, HttpError>> = send(request)
    @await(second)
}

start() {}

test "async HTTP send consumes the request owner" {}
