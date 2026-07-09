File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
close_file = @lib("file.do", close_file)

close_sample(file File) -> nil {
    close_file(file)
    return
}

start() {
    return
}
