_answer = @./fixture.value_only.do/_answer
counter = @./fixture.value_only.do/counter

test "top value only import" {
    counter = add(counter, 1)
    if eq(_answer, -42) return
    return
}
