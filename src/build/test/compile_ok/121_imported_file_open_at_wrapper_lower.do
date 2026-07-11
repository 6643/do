File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
open_file_at = @lib("file.do", open_file_at)

open_sample(dir File) -> File | FileError {
    path text = "data.txt"
    return open_file_at(dir, path)
}

start() {
    return
}
