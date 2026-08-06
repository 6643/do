send = @host_func("do:resource-probe-owned-error/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, OtherErrorResource>)

HttpRequest = @wasi_resource("do:resource-probe-owned-error/http/request", { .id i64 })
HttpResponse = @wasi_resource("do:resource-probe-owned-error/http/response", { .id i64 })
OtherErrorResource = @wasi_resource("do:resource-probe-owned-error/http/other-error", { .id i64 })

run(request HttpRequest) -> Result<HttpResponse, OtherErrorResource> {
    pending Future<Result<HttpResponse, OtherErrorResource>> = send(request)
    return @await(pending)
}

start() {}
