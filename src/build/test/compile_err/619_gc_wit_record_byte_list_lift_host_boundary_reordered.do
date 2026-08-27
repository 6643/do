read = @host_func("demo:marshal-record-byte-list-lift/api@1.0.0", "read", () -> Reading)

Reading {
    payload [u8]
    code u32
}

start() {}
