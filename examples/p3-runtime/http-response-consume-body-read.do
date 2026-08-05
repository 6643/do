consume_body = @host("wasi:http/types@0.3.0-rc-2025-09-16", "response.consume-body", (HttpResponse) -> Tuple<Stream<u8>, Future<Result<option<trailers>, HttpError>>>)
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
HttpError error = HttpFailure

async run(response HttpResponse) -> nil {
    handles Tuple<Stream<u8>, Future<Result<option<trailers>, HttpError>>> = consume_body(response)
    reader Stream<u8> = @get(handles, 0)
    completion Future<Result<option<trailers>, HttpError>> = @get(handles, 1)
    pending Future<Result<u8, nil>> = @next(reader)
    item Result<u8, nil> = await(pending)
    _ = item
    @cancel(completion)
}

start() {}
