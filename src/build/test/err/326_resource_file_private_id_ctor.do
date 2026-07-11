File = @lib("file.do", File)

test "resource file private id ctor" {
    _file File = File{id = 1}
    return
}
