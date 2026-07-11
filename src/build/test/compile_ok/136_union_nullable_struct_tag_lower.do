User {
    id i32
}

find_user(found bool) -> User | nil {
    user User = User{id = 7}
    if found return user
    return nil
}

start() {
    user User | nil = find_user(true)
    if @is(user, User) return
    if @eq(user, nil) return
    return
}
