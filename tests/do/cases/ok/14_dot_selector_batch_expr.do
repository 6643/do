User {
    name Text
    age i32
}

test "dot selector batch expr" {
    u = User{name: "tom", age: 18}
    fields = {.name, .age}
    vals = get(u, {.name, .age})
    u2 = set(u, {.name: "bob"})
    xs = set(List<i32>{1, 2}, {0: 10, 1: 20})
    if fields return
    if vals return
    if u2 return
    if xs return
}
