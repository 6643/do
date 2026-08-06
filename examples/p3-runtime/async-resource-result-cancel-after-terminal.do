send = @host_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)

HttpRequest = @wasi_resource("do:resource-probe/http/request", { .id i64 })
HttpResponse = @wasi_resource("do:resource-probe/http/response", { .id i64 })
HttpError error = HttpFailure

cancel_request(request HttpRequest) -> Result<HttpResponse, HttpError> {
    completion Future<Result<HttpResponse, HttpError>> = send(request)
    return @await(completion)
    @cancel(completion)
}

start() {}
