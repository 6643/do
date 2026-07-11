FileError error = NotFound
NetworkError error = Timeout
AppError error = FileError | NetworkError

test "error decl known error union" {
    return
}
