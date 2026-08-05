async ready() -> i32 {
    return 1
}

start() {
    pending Future<i32> = ready()
}
