write = @host_func("demo:marshal-record-two-u32-lists-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    first [u32]
    second [u32]
}

start() {
    value Writing = Writing{code = 7, first = .{10, 20, 5}, second = .{3, 4}}
    write(value)
}
