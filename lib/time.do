now = @env/now() -> i64
sleep = @env/sleep(i64) -> nil

ms(n i64) -> i64 {
    return n
}

sec(n i64) -> i64 {
    return mul(n, 1000)
}

min(n i64) -> i64 {
    return mul(n, 60000)
}

hour(n i64) -> i64 {
    return mul(n, 3600000)
}

day(n i64) -> i64 {
    return mul(n, 86400000)
}

unix_ms() -> i64 {
    return now()
}
