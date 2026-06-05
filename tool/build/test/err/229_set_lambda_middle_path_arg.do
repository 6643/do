Bag {
    items [i32]
}

test "set lambda middle path arg" {
    bag Bag = Bag{items = .{1, 2}}
    bag = set(bag, .items, (x i32) => x, 9)
    return
}
