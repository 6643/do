#T
pipe(value T, funcs ...(T) -> T) -> T {
    out T = value
    loop f, _ = funcs {
        out = f(out)
    }
    return out
}
