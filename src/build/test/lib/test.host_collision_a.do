host_value = @host_func("env", "one", () -> i32)

value() -> i32 {
    return host_value()
}
