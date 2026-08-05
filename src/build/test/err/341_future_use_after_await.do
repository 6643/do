async ready() -> i32 {
    return 1
}

async consume() -> i32 {
    pending Future<i32> = ready()
    first i32 = await(pending)
    return await(pending)
}

test "future is consumed once" {}
