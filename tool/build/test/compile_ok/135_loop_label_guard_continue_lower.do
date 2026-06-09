start() {
    xs [i32] = .{1, 2}
#outer
    loop value, index = xs {
        if @eq(index, 0) continue #outer
        if @eq(value, 2) break #outer
        value = value
    }
    return
}
