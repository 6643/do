read = @host_func("demo:marshal-record-byte-list-lift/api@1.0.0", "other", () -> Reading)

Reading {
    code u32
    payload [u8]
}

start() {}
