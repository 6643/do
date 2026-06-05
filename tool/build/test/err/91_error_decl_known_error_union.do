FileError error = NotFound
NetworkError error = Timeout
AppError = FileError | NetworkError

test "error decl known error union" {
    return
}
