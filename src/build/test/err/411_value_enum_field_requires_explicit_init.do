Status i32 = Ready(1) | Failed(2)

StatusHolder {
    status Status
}

test "value enum field has no implicit default" {
    result StatusHolder = StatusHolder{}
    return
}
