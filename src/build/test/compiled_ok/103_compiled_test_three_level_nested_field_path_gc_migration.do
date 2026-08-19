Leaf {
    value [u8]
    tag i32
}

Middle {
    leaf Leaf
    tag i32
}

Inner {
    middle Middle
    tag i32
}

Outer {
    inner Inner
    tag i32
}

update(outer Outer) -> Outer {
    return @set(outer, .inner, .middle, .leaf, .tag, 9)
}

test "compiled three-level nested field path preserves source" {
    old [u8] = "old"
    leaf Leaf = Leaf{value = old, tag = 3}
    middle Middle = Middle{leaf = leaf, tag = 7}
    inner Inner = Inner{middle = middle, tag = 5}
    box Outer = Outer{inner = inner, tag = 11}
    updated Outer = update(box)

    original_inner Inner = @get(box, .inner)
    original_middle Middle = @get(original_inner, .middle)
    original_leaf Leaf = @get(original_middle, .leaf)
    updated_inner Inner = @get(updated, .inner)
    updated_middle Middle = @get(updated_inner, .middle)
    updated_leaf Leaf = @get(updated_middle, .leaf)
    original_tag i32 = @get(original_leaf, .tag)
    updated_tag i32 = @get(updated_leaf, .tag)
    original_len i32 = @len(@get(original_leaf, .value))
    updated_len i32 = @len(@get(updated_leaf, .value))
    updated_inner_tag i32 = @get(updated_inner, .tag)
    updated_middle_tag i32 = @get(updated_middle, .tag)
    updated_outer_tag i32 = @get(updated, .tag)
    if @eq(original_tag, 3) {
        if @eq(updated_tag, 9) {
            if @eq(original_len, 3) {
                if @eq(updated_len, 3) {
                    if @eq(updated_inner_tag, 5) {
                        if @eq(updated_middle_tag, 7) {
                            if @eq(updated_outer_tag, 11) return
                        }
                    }
                }
            }
        }
    }
}
