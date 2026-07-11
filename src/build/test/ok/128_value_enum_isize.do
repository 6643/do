Status = @lib("./fixture.value_enum_isize.do", Status)
Failed = @lib("./fixture.value_enum_isize.do", Failed)

test "value enum isize carrier" {
    status Status = Failed
    if @eq(status, Failed) return
}
