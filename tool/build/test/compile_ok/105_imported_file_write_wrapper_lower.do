File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
write_file = @lib("file.do", write_file)

write_sample(file File) -> FileError | nil {
    data [u8] = "abc"
    return write_file(file, data, 0)
}

start() {
    return
}
