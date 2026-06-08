File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
FileOutcome = @lib("file.do", FileOutcome)
FileClosed = @lib("file.do", FileClosed)
FileOpenFailed = @lib("file.do", FileOpenFailed)
FileReadFailed = @lib("file.do", FileReadFailed)
FileWriteFailed = @lib("file.do", FileWriteFailed)
FileFlushFailed = @lib("file.do", FileFlushFailed)
FileCloseFailed = @lib("file.do", FileCloseFailed)
FileLinkFailed = @lib("file.do", FileLinkFailed)
is_file_closed = @lib("file.do", is_file_closed)
read_file = @lib("file.do", read_file)
write_file = @lib("file.do", write_file)
link_file = @lib("file.do", link_file)
open_file_at = @lib("file.do", open_file_at)
close_file = @lib("file.do", close_file)

accept_file(file File) {
    return
}

test "file lib resource shape" {
    err FileError = FileClosed
    link_err FileError = FileLinkFailed
    outcome FileOutcome = nil
    ok bool = @eq(outcome, nil)
    ok = @and(ok, is_file_closed(err))
    ok = @and(ok, @eq(link_err, FileLinkFailed))
    if ok return
}
