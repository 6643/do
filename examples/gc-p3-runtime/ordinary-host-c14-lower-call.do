write = @host_func("demo:marshal-record-nested-lower-deeper/api@1.0.0", "write", (Writing) -> nil)

Leaf {
    code u32
    count u64
}

Header {
    leaf Leaf
    status i64
}

Detail {
    header Header
    marker i64
}

Writing {
    detail Detail
    tail i64
}

start() {
    value Writing = Writing{detail = Detail{header = Header{leaf = Leaf{code = 7, count = 35}, status = -5}, marker = 11}, tail = -6}
    write(value)
}
