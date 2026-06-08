host_value = @env("two", () -> i32)

value() -> i32 {
    return host_value()
}
