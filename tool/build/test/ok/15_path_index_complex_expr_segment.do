List = @lib("list.do", List)
list_from_items = @lib("list.do", list_from_items)
list_add = @lib("list.do", list_add)
items = @lib("list.do", items)

User {
    name [u8]
}

test "path index complex expr segment" {
    raw [User] = .{}
    users List<User> = list_from_items(raw)
    users = list_add(users, User{name = "tom"})
    users = list_add(users, User{name = "amy"})
    i usize = 0
    first_name = @get(items(users), @add(i, 1), .name)
    expected [u8] = "amy"
    if @eq(first_name, expected) return
}
