factorial = @lib("./fixture.recursive_math.do", factorial)

test "imported recursive factorial" {
    out i32 = factorial(5)
    if @eq(out, 120) return
}
