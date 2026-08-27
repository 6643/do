read = @host_func("demo:marshal-record-u32-list-lift/api@1.0.0", "read", () -> Reading)

Reading {
    payload [u32]
    code u32
}

start() {}
