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

start() {}
