List = @list.do/List
list_from_items = @list.do/list_from_items
list_add = @list.do/list_add
items = @list.do/items

User {
    name [u8]
}

test "path index expr segment" {
    raw [User] = .{}
    users List<User> = list_from_items(raw)
    users = list_add(users, User{name = "tom"})
    first_name = get(items(users), 0, .name)
    expected [u8] = "tom"
    if eq(first_name, expected) return
}
