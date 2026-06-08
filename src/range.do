range_usize(from usize, end usize) -> [usize] {
    out [usize] = .{}
    i usize = from
    loop {
        if @ge(i, end) return out
        out = @put(out, i)
        i = @add(i, 1)
    }
}

range_i32(from i32, end i32) -> [i32] {
    out [i32] = .{}
    i i32 = from
    loop {
        if @ge(i, end) return out
        out = @put(out, i)
        i = @add(i, 1)
    }
}

repeat_usize(value usize, count usize) -> [usize] {
    out [usize] = .{}
    i usize = 0
    loop {
        if @ge(i, count) return out
        out = @put(out, value)
        i = @add(i, 1)
    }
}

repeat_i32(value i32, count usize) -> [i32] {
    out [i32] = .{}
    i usize = 0
    loop {
        if @ge(i, count) return out
        out = @put(out, value)
        i = @add(i, 1)
    }
}
