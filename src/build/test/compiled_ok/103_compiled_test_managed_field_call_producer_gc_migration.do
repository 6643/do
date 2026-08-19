Box {
    value [u8]
    tag i32
}

make() -> [u8] {
    return .{1, 2}
}

replace(box Box) -> Box {
    return @set(box, .value, make())
}

test "compiled managed field call producer preserves source" {
    old [u8] = "old"
    box Box = Box{value = old, tag = 7}
    updated Box = replace(box)

    original_value [u8] = @get(box, .value)
    updated_value [u8] = @get(updated, .value)
    original_len i32 = @len(original_value)
    updated_len i32 = @len(updated_value)
    updated_tag i32 = @get(updated, .tag)
    if @eq(original_len, 3) {
        if @eq(updated_len, 2) {
            if @eq(updated_tag, 7) return
        }
    }
}
