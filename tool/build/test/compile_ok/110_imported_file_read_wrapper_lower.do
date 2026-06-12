File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
read_file = @lib("file.do", read_file)

read_sample(file File) -> [u8], bool, FileError | nil {
    return read_file(file, 0, 16)
}

start() {
    return
}
