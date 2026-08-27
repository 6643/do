read = @host_func("demo:marshal-record-mixed-text-two-u32-lists-lift/api@1.0.0", "other", () -> Reading)

Reading {
    code u32
    label text
    first [u32]
    second [u32]
}

start() {}
