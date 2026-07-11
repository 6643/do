Config {
    retries i32 = 3
    port i32 = 8080
    secure bool = false
}

start() {
    cfg Config = Config{port = 9000}
    retries i32 = @get(cfg, .retries)
    secure bool = @get(cfg, .secure)
    return
}
