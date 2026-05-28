inc = @fixture/import_overload_func.do/inc

use(f (i32) -> i32) -> i32 {
    return f(1)
}

use(f (i64) -> i64) -> i64 {
    return f(1)
}

test "import function name value ambiguous target" {
    v = use(inc)
    return
}
