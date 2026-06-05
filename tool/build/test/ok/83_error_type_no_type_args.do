FileError error = NotFound | PermissionDenied

test "error type no type args" {
    err FileError = NotFound
    return
}
