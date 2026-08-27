write = @host_func("demo:marshal-record-u32-list-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    payload [u32]
}

start() {
    value Writing = Writing{code = 7, payload = .{10, 20, 30}}
    write(value)
}
