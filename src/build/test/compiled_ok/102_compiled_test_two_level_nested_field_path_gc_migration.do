Leaf {
    value [u8]
    tag i32
}

Inner {
    leaf Leaf
    tag i32
}

Outer {
    inner Inner
    tag i32
}

update(outer Outer) -> Outer {
    return @set(outer, .inner, .leaf, .tag, 9)
}

test "compiled two-level nested field path preserves source" {
    old [u8] = "old"
    leaf Leaf = Leaf{value = old, tag = 3}
    inner Inner = Inner{leaf = leaf, tag = 5}
    box Outer = Outer{inner = inner, tag = 7}
    updated Outer = update(box)

    original_inner Inner = @get(box, .inner)
    original_leaf Leaf = @get(original_inner, .leaf)
    updated_inner Inner = @get(updated, .inner)
    updated_leaf Leaf = @get(updated_inner, .leaf)
    original_tag i32 = @get(original_leaf, .tag)
    updated_tag i32 = @get(updated_leaf, .tag)
    original_len i32 = @len(@get(original_leaf, .value))
    updated_len i32 = @len(@get(updated_leaf, .value))
    updated_inner_tag i32 = @get(updated_inner, .tag)
    updated_outer_tag i32 = @get(updated, .tag)
    if @eq(original_tag, 3) {
        if @eq(updated_tag, 9) {
            if @eq(original_len, 3) {
                if @eq(updated_len, 3) {
                    if @eq(updated_inner_tag, 5) {
                        if @eq(updated_outer_tag, 7) return
                    }
                }
            }
        }
    }
}
