FileError error = NotFound | PermissionDenied

test "error type args" {
    err FileError<i32> = NotFound
    return
}
