test "fields unknown type" {
    loop field = fields(Missing) {
        _ = @field_name(field)
    }
    return
}
