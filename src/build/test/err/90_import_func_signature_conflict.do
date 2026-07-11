inc = @lib("./fixture.import_overload_func.do", inc)

.inc(x i32) -> i32 {
    return x
}

test "import func signature conflict" {
    return
}
