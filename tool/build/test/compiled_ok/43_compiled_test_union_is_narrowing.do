PickError error = PickMissing | PickClosed

User {
    id i32
}

pick_i32(kind i32) -> i32 | text {
    if @eq(kind, 1) return 7
    return "seven"
}

pick_user(found bool) -> User | nil {
    user User = User{id = 9}
    if found return user
    return nil
}

pick_error(kind i32) -> i32 | PickError {
    if @eq(kind, 1) return 11
    return PickClosed
}

test "compiled is narrows scalar branch" {
    value i32 | text = pick_i32(1)
    if @is(value, i32) {
        x i32 = value
        if @eq(x, 7) return
    }
}

test "compiled is narrows struct branch" {
    value User | nil = pick_user(true)
    if @is(value, User) {
        user User = value
        if @eq(@get(user, .id), 9) return
    }
}

test "compiled is narrows error branch" {
    value i32 | PickError = pick_error(2)
    if @is(value, PickError) {
        err PickError = value
        if @eq(err, PickClosed) return
    }
}
