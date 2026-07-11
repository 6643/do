FileError error = NotFound

test "fields non struct type" {
    loop field = fields(FileError) {
        _ = @field_name(field)
    }
    return
}
