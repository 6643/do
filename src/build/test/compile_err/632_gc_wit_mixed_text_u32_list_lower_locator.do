write = @host_func("demo:marshal-record-mixed-text-u32-list-other/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    payload [u32]
}

start() {}
