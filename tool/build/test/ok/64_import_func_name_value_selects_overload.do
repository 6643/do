inc = @fixture/import_overload_func.do/inc

apply(f (i32) -> i32) -> i32 {
    return f(1)
}

test "import function name value selects overload" {
    v = apply(inc)
    return
}
