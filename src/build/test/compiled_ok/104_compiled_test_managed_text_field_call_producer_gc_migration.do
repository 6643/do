Box {
    value text
    tag i32
}

make_text() -> text {
    return "fresh"
}

replace(box Box) -> Box {
    return @set(box, .value, make_text())
}

test "compiled managed text field call producer preserves source" {
    old text = "old"
    box Box = Box{value = old, tag = 7}
    updated Box = replace(box)

    original_value text = @get(box, .value)
    updated_value text = @get(updated, .value)
    original_len i32 = @len(original_value)
    updated_len i32 = @len(updated_value)
    updated_tag i32 = @get(updated, .tag)
    if @eq(original_len, 3) {
        if @eq(updated_len, 5) {
            if @eq(updated_tag, 7) return
        }
    }
}
