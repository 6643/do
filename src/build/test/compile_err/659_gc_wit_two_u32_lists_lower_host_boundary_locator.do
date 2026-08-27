write = @host_func("demo:marshal-record-two-u32-lists-other/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    first [u32]
    second [u32]
}

start() {}
