FileError error = FileClosed | FileWriteFailed

status_to_error(code i32, fallback FileError) -> FileError | nil {
    if @eq(code, 0) return nil
    if @eq(code, 1) return FileClosed
    return fallback
}

wrap_status(code i32) -> FileError | nil {
    return status_to_error(code, FileWriteFailed)
}

start() {
    return
}
