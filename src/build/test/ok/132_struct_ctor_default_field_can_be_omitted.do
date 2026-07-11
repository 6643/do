Config {
    port i32 = 8080
    name i32
}

test "struct ctor default field can be omitted" {
    cfg Config = Config{name = 1}
    if @eq(@get(cfg, .name), 1) return
}
