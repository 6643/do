consume_body = @host_func("wasi:http/types@0.3.0-rc-2025-09-16", "response.consume-body", (HttpResponse) -> Tuple<Stream<u8>, Future<Result<option<trailers>, HttpError>>>)
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
HttpError error = HttpFailure

run(response HttpResponse) -> nil {
    handles Tuple<Stream<u8>, Future<Result<option<trailers>, HttpError>>> = consume_body(response)
    reader Stream<u8> = @get(handles, 0)
    completion Future<Result<option<trailers>, HttpError>> = @get(handles, 1)
    pending Future<Result<u8, nil>> = @next(reader)
    first Result<u8, nil> = @await(pending)
    _ = first
    pending_2 Future<Result<u8, nil>> = @next(reader)
    second Result<u8, nil> = @await(pending_2)
    _ = second
    pending_3 Future<Result<u8, nil>> = @next(reader)
    third Result<u8, nil> = @await(pending_3)
    _ = third
    pending_4 Future<Result<u8, nil>> = @next(reader)
    fourth Result<u8, nil> = @await(pending_4)
    _ = fourth
    @cancel(completion)
}

start() {}
