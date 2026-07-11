id(x i32) -> i32 {
    return x
}

Status i8 = Ready(1) | Done(2)

test "wit scalar names" {
    x i32 = id(1)
    offset isize = -1
    status Status = Ready
    ok bool = @eq(offset, -1)
    ok = @and(ok, @eq(status, Ready))
    if ok return
    return
}
