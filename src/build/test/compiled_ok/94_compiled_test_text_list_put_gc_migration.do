append(input [text], value text) -> [text] {
    return @put(input, value)
}

test "compiled text list put preserves source and appends value" {
    first text = "a"
    second text = "bc"
    input [text] = .{first}
    result [text] = @put(input, second)
    if @eq(@len(input), 1) {
        if @eq(@len(result), 2) {
            old text = @get(input, 0)
            added text = @get(result, 1)
            if @eq(@len(old), 1) {
                if @eq(@len(added), 2) return
            }
        }
    }
}
