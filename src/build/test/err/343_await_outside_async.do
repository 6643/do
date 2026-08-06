start() {
    pending Future<i32> = nil
    value i32 = @await(pending)
}

test "await requires async" {}
