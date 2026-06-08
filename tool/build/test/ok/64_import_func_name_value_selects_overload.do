inc = @lib("./fixture.import_overload_func.do", inc)

#F = (i32) -> i32
apply(f F) -> i32 {
    return f(1)
}

test "import function name value selects overload" {
    v = apply(inc)
    return
}
