FileError error = FileOpenFailed | FileClosed | FileReadFailed | FileWriteFailed | FileFlushFailed | FileCloseFailed

host_file_close = @env/file_close(i64) -> i32
host_file_flush = @env/file_flush(i64) -> i32

File {
    .id i64
}

.file_from_id(id i64) -> File | FileError {
    if lt(id, 0) return FileOpenFailed
    return File{id = id}
}

.file_id(file File) -> i64 {
    return get(file, .id)
}

.file_status_to_error(code i32, fallback FileError) -> FileError | nil {
    if eq(code, 0) return nil
    if eq(code, 1) return FileClosed
    return fallback
}

close_file(file File) -> FileError | nil {
    code i32 = host_file_close(file_id(file))
    return file_status_to_error(code, FileCloseFailed)
}

flush_file(file File) -> FileError | nil {
    code i32 = host_file_flush(file_id(file))
    return file_status_to_error(code, FileFlushFailed)
}

is_file_closed(err FileError) -> bool {
    return eq(err, FileClosed)
}
