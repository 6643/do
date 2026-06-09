local_value = @lib("./fixture.dep_shadow.do", value)
dep_value = @lib("~/fixture.dep_shadow.do", value)

start() {
    a i32 = local_value()
    b i32 = dep_value()
    if @eq(a, b) return
    return
}
