read = @host_func("demo:marshal-record-managed-lift-multi/api@1.0.0", "other", () -> Reading)

Reading {
    code u32
    label text
    note text
}

start() {}
