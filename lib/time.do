// Declarative WASI host bindings (record + funcs). Public API unchanged.
// Host imports must stay in the import prefix (before other decls).
.host_now = @wasi_func("clocks/system-clock/now", () -> Datetime)
.host_resolution = @wasi_func("clocks/system-clock/get-resolution", () -> u64)
.host_monotonic_now = @wasi_func("clocks/monotonic-clock/now", () -> u64)
.host_monotonic_resolution = @wasi_func("clocks/monotonic-clock/get-resolution", () -> u64)

Datetime = @wasi_record("clocks/wall-clock/datetime", {
    seconds i64
    nanoseconds u32
})

now() -> Datetime {
    return host_now()
}

resolution() -> u64 {
    return host_resolution()
}

monotonic_now() -> u64 {
    return host_monotonic_now()
}

monotonic_resolution() -> u64 {
    return host_monotonic_resolution()
}

ms(n i64) -> i64 {
    return n
}

sec(n i64) -> i64 {
    return @mul(n, 1000)
}

minute(n i64) -> i64 {
    return @mul(n, 60000)
}

hour(n i64) -> i64 {
    return @mul(n, 3600000)
}

day(n i64) -> i64 {
    return @mul(n, 86400000)
}

unix_ms() -> i64 {
    current Datetime = now()
    sec_ms i64 = @mul(@get(current, .seconds), 1000)
    ns_ms i64 = @as(i64, @div(@get(current, .nanoseconds), 1000000))
    return @add(sec_ms, ns_ms)
}
