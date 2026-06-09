FileError error = FileMissing | FileDenied

read_code(kind i32) -> i32 | FileError | nil {
    if @eq(kind, 0) return nil
    if @eq(kind, 1) return 42
    return FileDenied
}

start() {
    result i32 | FileError | nil = read_code(2)
    if @is(result, FileError) return
    if @eq(result, nil) return
    return
}
