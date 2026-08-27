read = @host_func("demo:marshal-record-u32-list-lift/api@1.0.0", "read", () -> Reading)

Reading {
    code u32
    payload [u32]
    extra u32
}

start() {}
