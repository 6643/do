test "compiled storage alias set keeps old value" {
    data [u8] = "abc"
    alias [u8] = data
    next [u8] = @set(data, 1, 90)

    ok bool = true
    ok = @and(ok, @eq(@get(alias, 1), 98))
    ok = @and(ok, @eq(@get(next, 1), 90))
    ok = @and(ok, @eq(@len(alias), 3))
    ok = @and(ok, @eq(@len(next), 3))
    if ok return
}
