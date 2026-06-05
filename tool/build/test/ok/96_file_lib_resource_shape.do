File = @file.do/File
FileError = @file.do/FileError
FileClosed = @file.do/FileClosed
FileOpenFailed = @file.do/FileOpenFailed
FileReadFailed = @file.do/FileReadFailed
FileWriteFailed = @file.do/FileWriteFailed
FileFlushFailed = @file.do/FileFlushFailed
FileCloseFailed = @file.do/FileCloseFailed
is_file_closed = @file.do/is_file_closed

accept_file(file File) {
    return
}

test "file lib resource shape" {
    err FileError = FileClosed
    if is_file_closed(err) return
}
