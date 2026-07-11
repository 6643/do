Status = @lib("~/test.value_enum_isize.do", Status)
Failed = @lib("~/test.value_enum_isize.do", Failed)
Bad = @lib("~/test.value_enum_isize.do", Failed)

test "compiled value enum isize carrier" {
    status Status = Failed
    if @eq(status, Failed) return
}

test "compiled value enum branch alias carrier" {
    status Status = Bad
    if @eq(status, Bad) return
}
