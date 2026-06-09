cleanup = @lib("./fixture.defer_nil.do", cleanup)

test "imported defer nil" {
    defer cleanup()
    return
}
