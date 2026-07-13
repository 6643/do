host_value = @host("env", "one", () -> i32)

value() -> i32 {
    return host_value()
}
