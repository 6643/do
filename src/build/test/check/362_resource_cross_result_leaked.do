create_request = @host("do:resource-probe/http@0.1.0", "create-request", () -> HttpRequest)
send = @host("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)

HttpRequest = @wasi_resource("do:resource-probe/http/request", { .id i64 })
HttpResponse = @wasi_resource("do:resource-probe/http/response", { .id i64 })
HttpError error = HttpFailure

start() {
    request HttpRequest = create_request()
    replied Result<HttpResponse, HttpError> = send(request)
    if @is(replied, Ok) {
        response HttpResponse = replied
    }
}

test "cross-resource Result payload must be ended" {}
