#A = i32
use(x A) -> i32 {
    return x
}

#A = i64
use(x A) -> i64 {
    return x
}

test "scalar constraint name not signature alias" {
    v = use(1)
    return
}
