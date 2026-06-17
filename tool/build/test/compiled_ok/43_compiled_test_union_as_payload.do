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

test "compiled union as scalar payload" {
    value i32 | text = pick_i32(1)
    if @is(value, i32) {
        x i32 = @as(value, i32)
        if @eq(x, 7) return
    }
}

test "compiled union as struct payload" {
    value User | nil = pick_user(true)
    if @is(value, User) {
        user User = @as(value, User)
        if @eq(@get(user, .id), 9) return
    }
}

test "compiled union as error payload" {
    value i32 | PickError = pick_error(2)
    if @is(value, PickError) {
        err PickError = @as(value, PickError)
        if @eq(err, PickClosed) return
    }
}
