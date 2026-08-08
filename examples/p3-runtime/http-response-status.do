get_status = @host_func("wasi:http/types@0.3.0-rc-2025-09-16", "response.get-status-code", (HttpResponse) -> u16)
drop_response = @host_func("wasi:http/types@0.3.0-rc-2025-09-16", "response.drop", (HttpResponse) -> nil)
HttpResponse = @wasi_resource("http/types/response", { .id i64 })
run(response HttpResponse) -> u16 {
    status u16 = get_status(response)
    drop_response(response)
    return status
}
start() {}
