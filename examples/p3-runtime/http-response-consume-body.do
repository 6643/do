consume_body = @host_func("wasi:http/types@0.3.0-rc-2025-09-16", "response.consume-body", (HttpResponse) -> Tuple<Stream<u8>, Future<Result<option<trailers>, HttpError>>>)
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
HttpError error = HttpFailure

run(response HttpResponse) -> nil {
    _ = consume_body(response)
}

start() {}
