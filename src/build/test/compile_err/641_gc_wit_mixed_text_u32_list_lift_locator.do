read = @host_func("demo:other/api@1.0.0", "read", () -> Reading)

Reading {
    code u32
    label text
    payload [u32]
}

start() {}
