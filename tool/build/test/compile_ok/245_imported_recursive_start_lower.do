factorial = @lib("~/test.recursive_math.do", factorial)

start() {
    out i32 = factorial(5)
    if @eq(out, 120) return
    return
}
