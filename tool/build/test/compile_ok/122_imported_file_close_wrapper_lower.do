File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
close_file = @lib("file.do", close_file)

close_sample(file File) -> FileError | nil {
    return close_file(file)
}

start() {
    return
}
