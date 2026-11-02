Status i32 = Ready(1) | Failed(2)

StatusHolder {
    status Status | nil = nil
}

test "value enum nullable explicit nil" {
    other Status | nil = nil
    other = Ready
    if @eq(other, Ready) return
}

test "value enum nullable struct field" {
    result StatusHolder = StatusHolder{status = nil}
    result = @set(result, .status, Ready)
    explicit StatusHolder = StatusHolder{status = Ready}
    return
}
