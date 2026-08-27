Core {
    value [u8]
    tag i32
}

Leaf {
    core Core
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

Top {
    outer Outer
    tag i32
}

update(top Top) -> Top {
    return @set(top, .outer, .inner, .middle, .leaf, .core, .tag, 13)
}

test "compiled five-level nested field path preserves source" {
    old [u8] = "old"
    core Core = Core{value = old, tag = 3}
    leaf Leaf = Leaf{core = core, tag = 5}
    middle Middle = Middle{leaf = leaf, tag = 7}
    inner Inner = Inner{middle = middle, tag = 9}
    outer Outer = Outer{inner = inner, tag = 11}
    top Top = Top{outer = outer, tag = 15}
    updated Top = update(top)

    original_outer Outer = @get(top, .outer)
    original_inner Inner = @get(original_outer, .inner)
    original_middle Middle = @get(original_inner, .middle)
    original_leaf Leaf = @get(original_middle, .leaf)
    original_core Core = @get(original_leaf, .core)
    updated_outer Outer = @get(updated, .outer)
    updated_inner Inner = @get(updated_outer, .inner)
    updated_middle Middle = @get(updated_inner, .middle)
    updated_leaf Leaf = @get(updated_middle, .leaf)
    updated_core Core = @get(updated_leaf, .core)
    original_tag i32 = @get(original_core, .tag)
    original_direct_tag i32 = @get(top, .outer, .inner, .middle, .leaf, .core, .tag)
    updated_tag i32 = @get(updated_core, .tag)
    original_len i32 = @len(@get(original_core, .value))
    updated_len i32 = @len(@get(updated_core, .value))
    updated_leaf_tag i32 = @get(updated_leaf, .tag)
    updated_middle_tag i32 = @get(updated_middle, .tag)
    updated_inner_tag i32 = @get(updated_inner, .tag)
    updated_outer_tag i32 = @get(updated_outer, .tag)
    updated_top_tag i32 = @get(updated, .tag)
    if @eq(original_tag, 3) {
        if @eq(original_direct_tag, 3) {
            if @eq(updated_tag, 13) {
                if @eq(original_len, 3) {
                    if @eq(updated_len, 3) {
                        if @eq(updated_leaf_tag, 5) {
                            if @eq(updated_middle_tag, 7) {
                                if @eq(updated_inner_tag, 9) {
                                    if @eq(updated_outer_tag, 11) {
                                        if @eq(updated_top_tag, 15) return
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
