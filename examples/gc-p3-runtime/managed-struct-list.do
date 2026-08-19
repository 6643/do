Box {
    value [u8]
    tag i32
}

make_boxes() -> [Box] {
    bytes [u8] = .{7, 12, 17}
    one Box = Box{value = bytes, tag = 7}
    boxes [Box] = .{one}
    count i32 = @len(boxes)
    first Box = @get(boxes, 0)
    loop item, index = boxes {
        tag i32 = @get(item, .tag)
        if @eq(index, 0) break
    }
    return boxes
}

append(boxes [Box], value Box) -> [Box] {
    return @put(boxes, value)
}

start() {}
