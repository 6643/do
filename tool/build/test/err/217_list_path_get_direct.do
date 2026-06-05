List = @list.do/List
list_from_items = @list.do/list_from_items
list_add = @list.do/list_add

User {
    name [u8]
}

test "list path get direct" {
    raw [User] = .{}
    users List<User> = list_from_items(raw)
    users = list_add(users, User{name = "tom"})
    name = get(users, 0, .name)
    return
}
