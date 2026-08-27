write = @host_func("demo:other/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    note text
}

start() {}
