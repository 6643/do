limit i32 = 1

use(limit i32) -> i32 {
    return limit
}

test "func param shadows top value" {
    value = use(1)
    consume(value)
}
