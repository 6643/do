File {
    .id i64
}

file_id(file File) -> i64 {
    return @get(file, .id)
}

start() {
    return
}
