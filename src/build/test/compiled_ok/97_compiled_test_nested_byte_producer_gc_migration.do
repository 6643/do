Box {
    value [u8]
    tag i32
}

test "compiled nested byte producer preserves source" {
    input [u8] = .{1, 2, 3}
    box Box = Box{value = input, tag = 7}
    updated Box = @set(box, .value, @set(@get(box, .value), 1, 65))

    old [u8] = @get(box, .value)
    next [u8] = @get(updated, .value)
    if @eq(@len(old), 3) {
        if @eq(@len(next), 3) {
            if @eq(@get(updated, .tag), 7) return
        }
    }
}
