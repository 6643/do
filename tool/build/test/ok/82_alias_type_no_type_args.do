User {
    id i32
}

MaybeUser = User | nil

test "union alias no type args" {
    user MaybeUser = nil
    return
}
