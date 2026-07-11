value = @lib("~/test.missing_helper.do", value)

helper() -> i32 {
    return 99
}

start() {
    x i32 = value()
    return
}
