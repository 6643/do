send = @host("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)

HttpRequest = @wasi_resource("http/types/request", { .id i64 })
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
HttpError error = HttpFailure

start() {
    request HttpRequest = nil
    replied Result<HttpResponse, HttpError> = send(request)
    _ = replied
}
