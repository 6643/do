PickError error = PickBad

pick_bytes() -> [u16] | PickError {
    return .{55357, 56832}
}

test "compiled union storage payload len get lower" {
    bytes = pick_bytes()
    ok bool = false
    if @is(bytes, [u16]) {
        ok = true
        ok = @and(ok, @eq(@len(bytes), 2))
        ok = @and(ok, @eq(@get(bytes, 0), 55357))
        ok = @and(ok, @eq(@get(bytes, 1), 56832))
    }
    if ok return
}
