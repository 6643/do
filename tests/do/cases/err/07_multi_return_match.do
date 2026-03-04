pair(a i32, b i32) i32, i32 {
    return a, b
}

_start() {
    match pair(1, 2) {
        _ => return,
    }
}

