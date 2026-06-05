User {
    id i32
}

MaybeUser = User | nil

test "alias type args" {
    user MaybeUser<i32> = nil
    return
}
