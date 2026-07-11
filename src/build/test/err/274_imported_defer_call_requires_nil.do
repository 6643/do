value = @lib("./fixture.defer_non_nil.do", value)

test "imported defer call requires nil" {
    defer value()
    return
}
