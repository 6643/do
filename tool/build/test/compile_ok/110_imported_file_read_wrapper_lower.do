File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
FileOutcome = @lib("file.do", FileOutcome)
read_file = @lib("file.do", read_file)

read_sample(file File) -> [u8], bool, FileOutcome {
    return read_file(file, 0, 16)
}

start() {
    return
}
