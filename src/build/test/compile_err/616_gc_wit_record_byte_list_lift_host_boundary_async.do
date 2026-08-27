read = @host_async_func("demo:marshal-record-byte-list-lift/api@1.0.0", "read", () -> Reading)

Reading {
    code u32
    payload [u8]
}

start() {}
