inc = @./fixture.import_overload_func.do/inc

#F32 = (i32) -> i32
use(f F32) -> i32 {
    return f(1)
}

#F64 = (i64) -> i64
use(f F64) -> i64 {
    return f(1)
}

test "import function name value ambiguous target" {
    v = use(inc)
    return
}
