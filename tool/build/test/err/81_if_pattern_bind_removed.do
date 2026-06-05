FileError error = NotFound

read_file(path [u8]) -> [u8] | FileError {
    return NotFound
}

test "if pattern bind removed" {
    if FileError(err) := read_file("config") return err
}
