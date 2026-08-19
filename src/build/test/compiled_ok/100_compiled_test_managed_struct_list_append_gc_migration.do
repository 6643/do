Box {
    value [u8]
    tag i32
}

test "compiled managed struct list append preserves source values" {
    bytes [u8] = "abc"
    extra [u8] = "def"
    first Box = Box{value = bytes, tag = 7}
    second Box = Box{value = extra, tag = 9}
    boxes [Box] = .{first}
    updated [Box] = @put(boxes, second)

    if @eq(@len(boxes), 1) {
        if @eq(@len(updated), 2) return
    }
}
