read = @host_func("demo:marshal-record-byte-list-lift/wrong@1.0.0", "read", () -> Reading)

Reading {
    code u32
    payload [u8]
}

start() {}
