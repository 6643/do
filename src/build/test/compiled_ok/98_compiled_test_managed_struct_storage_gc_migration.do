Box {
    value [u8]
    tag i32
}

test "compiled managed struct storage update preserves source" {
    input [u8] = "abc"
    box Box = Box{value = input, tag = 1}
    updated Box = @set(box, .tag, 7)
    old_value [u8] = @get(box, .value)
    new_value [u8] = @get(updated, .value)
    old_tag i32 = @get(box, .tag)
    new_tag i32 = @get(updated, .tag)
    old_len i32 = @len(old_value)
    new_len i32 = @len(new_value)

    if @eq(old_tag, 1) {
        if @eq(new_tag, 7) {
            if @eq(old_len, 3) {
                if @eq(new_len, 3) return
            }
        }
    }
}
