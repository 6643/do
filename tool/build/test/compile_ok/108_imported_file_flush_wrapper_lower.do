File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
flush_file = @lib("file.do", flush_file)

flush_sample(file File) -> FileError | nil {
    return flush_file(file)
}

start() {
    return
}
