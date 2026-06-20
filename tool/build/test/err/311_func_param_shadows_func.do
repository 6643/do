helper() -> i32 {
    return 1
}

use(helper i32) -> i32 {
    return helper
}

test "func param shadows func" {
    value = use(1)
    consume(value)
}
