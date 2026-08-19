test "compiled text identity preserves value" {
    value text = "hello"
    alias text = value
    if @eq(alias, "hello") return
}
