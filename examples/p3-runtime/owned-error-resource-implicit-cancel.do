send = @host_async_func("do:resource-probe-owned-error/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpErrorResource>)

HttpRequest = @wasi_resource("do:resource-probe-owned-error/http/request", { .id i64 })
HttpResponse = @wasi_resource("do:resource-probe-owned-error/http/response", { .id i64 })
HttpErrorResource = @wasi_resource("do:resource-probe-owned-error/http/error-resource", { .id i64 })

run(request HttpRequest) -> nil {
    completion Future<Result<HttpResponse, HttpErrorResource>> = send(request)
}

start() {}
