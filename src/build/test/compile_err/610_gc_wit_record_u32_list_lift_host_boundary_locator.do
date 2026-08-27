read = @host_func("demo:other/api@1.0.0", "read", () -> Reading)

Reading {
    code u32
    payload [u32]
}

start() {}
