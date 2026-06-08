File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
link_file = @lib("file.do", link_file)

link_sample(old_file File, new_file File) -> FileError | nil {
    old_path text = "old.txt"
    new_path text = "new.txt"
    return link_file(old_file, old_path, new_file, new_path)
}

start() {
    return
}
