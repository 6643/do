start() {
    pending Future<i32> = nil
    @cancel(pending)
}

test "cancel requires async" {}
