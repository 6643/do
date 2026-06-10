TodoItem {
    title i32
}

#T
#U
#Q = (T) -> U
project(x T, f Q) -> U {
    return f(x)
}

test "lambda body path get" {
    todo TodoItem = TodoItem{title = 42}
    value i32 = project(todo, (todo TodoItem) -> i32 => @get(todo, .title))
    if @eq(value, 42) return
}
