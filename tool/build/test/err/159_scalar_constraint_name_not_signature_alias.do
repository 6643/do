#A
use(x A) -> i32 {
    return 1
}

#A
use(x A) -> i64 {
    return 2
}

test "scalar constraint name not signature alias" {
    v = use(1)
    return
}
