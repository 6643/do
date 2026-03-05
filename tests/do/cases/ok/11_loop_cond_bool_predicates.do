User {
    id i32
}

is_valid(u User) bool => true
has(user_map i32, uid i32) bool => true

test "loop cond bool predicates" {
    loop is_valid(User{id: 1}) {
        break
    }

    user_map = 1
    uid = 2
    loop has(user_map, uid) {
        break
    }
}
