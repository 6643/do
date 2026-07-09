factorial = @lib("~/test.recursive_math.do", factorial)

test "compiled imported recursive factorial" {
    out i32 = factorial(5)
    if @eq(out, 120) return
}
