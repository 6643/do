Result<T | E> = Ok(T) | Err(E)
Result<T> = Ok(T) | Err(T)

ByteKind<u8> = ByteSpace(1) | ByteDigit(2) | ByteLetter(3)

Message = Quit | Text([u8]) | Binary([u8]) | TcpAddr(IpSocketAddress)
Message<nil | [u8] | IpSocketAddress> = Quit(nil) | Text([u8]) | Binary([u8]) | TcpAddr(IpSocketAddress)

@host_func("wasi:clocks")

Instant {
seconds i64
nanoseconds u32
}

now(clock Clock) -> Instant

```
Box {
    has_tag bool
    age u32
}
update(box Box) -> nil {
    @set(box, .has_tag, false)
}

start(){
    b = Box{has_tag = true, age = 18}
    update(b) // 默认引用传递
    a = b // 手动显式克隆, 这个时候是有两份的, 不要再隐式了。
    // 基本类型是值传递, i32/i8/f32/bool/...
    // 复杂类型是引用传递, struct/array/string/...
    // 所以暂时不用添加借用和所有权, 这应该是能处理吧？
    // 这样就能避免多分配内存
}



  @get(value T, path...) -> V
  @get(target ref<T>, path...) -> nil

  @set(value T, path..., value V) -> T
  @set(target ref<T>, path..., value V) -> nil



Box{
    value ref<u32>
}

```
