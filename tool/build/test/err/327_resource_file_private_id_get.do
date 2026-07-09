File = @lib("file.do", File)

peek_file_id(file File) -> i64 {
    return @get(file, .id)
}

test "resource file private id get" {
    return
}
