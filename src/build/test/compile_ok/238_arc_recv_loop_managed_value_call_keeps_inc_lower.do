Box {
    value [u8]
}

take(box Box) -> i32 {
    value [u8] = @get(box, .value)
    return @len(value)
}

start() {
    bytes [u8] = "abc"
    one Box = Box{value = bytes}
    boxes [Box] = .{one}
    loop item, count = recv(boxes) {
        n i32 = take(item)
        if @eq(count, 0) break
    }
    return
}
