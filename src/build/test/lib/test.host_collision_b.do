host_value = @host_func("env", "two", () -> i32)

value() -> i32 {
    return host_value()
}
