read = @host_async_func("demo:marshal-record-nested-lift-deeper/api@1.0.0", "read", () -> Reading)

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

Reading {
    detail Detail
    tail i64
}

start() {}
