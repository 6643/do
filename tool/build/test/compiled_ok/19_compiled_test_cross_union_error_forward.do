CrossError = @lib("~/test.cross_union_error_forward.do", CrossError)
forward_error = @lib("~/test.cross_union_error_forward.do", forward_error)

test "compiled cross union error forward" {
    result = forward_error(120)
    if @is(result, CrossError) return
}
