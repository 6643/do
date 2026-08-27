read = @host_func("demo:other/api@1.0.0", "read", () -> Reading)

Reading {
    code u32
    label text
    note text
}

start() {}
