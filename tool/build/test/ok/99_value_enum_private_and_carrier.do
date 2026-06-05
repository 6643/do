.InternalStatus i8 = Ready(1) | .Hidden(-1)

test "private value enum branch" {
    status InternalStatus = Hidden
    if eq(status, Hidden) return
    return
}
