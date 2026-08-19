Inner {
    tag i32
    value [u8]
}

Outer {
    inner Inner
    id i32
}

update(outer Outer) -> Outer {
    return @set(outer, .inner, .tag, 9)
}

test "compiled nested field path preserves source" {
    old [u8] = "old"
    child Inner = Inner{tag = 3, value = old}
    box Outer = Outer{inner = child, id = 7}
    updated Outer = update(box)

    original_child Inner = @get(box, .inner)
    updated_child Inner = @get(updated, .inner)
    original_tag i32 = @get(original_child, .tag)
    updated_tag i32 = @get(updated_child, .tag)
    original_value [u8] = @get(original_child, .value)
    updated_value [u8] = @get(updated_child, .value)
    original_len i32 = @len(original_value)
    updated_len i32 = @len(updated_value)
    updated_id i32 = @get(updated, .id)
    if @eq(original_tag, 3) {
        if @eq(updated_tag, 9) {
            if @eq(original_len, 3) {
                if @eq(updated_len, 3) {
                    if @eq(updated_id, 7) return
                }
            }
        }
    }
}
