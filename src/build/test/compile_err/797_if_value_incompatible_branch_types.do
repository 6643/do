start() {
    cond bool = true
    wide i64 = 2
    count i32 = if cond 1 else wide
    return
}
