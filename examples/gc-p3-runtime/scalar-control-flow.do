choose(value i32) -> i32 {
    if @eq(value, 0) {
        return 7
    } else {
        return value
    }
}

guard(value i32) -> i32 {
    if @eq(value, 0) return 7
    return value
}

choose_chain(value i32) -> i32 {
    if @eq(value, 0) {
        return 7
    } else if @eq(value, 1) {
        return 8
    } else {
        return value
    }
}

start() {}
