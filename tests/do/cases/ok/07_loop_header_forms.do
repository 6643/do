test "loop header forms" {
    count = 0
    loop lt(count, 3) {
        print("count = $count")
        count = add(count, 1)
    }

    list_a = List<i8>{1, 2, 3, 4, 5, 6, 7, 8, 9, 0}

    loop val, index := list_a {
        print(val, index)
    }

    loop val := list_a {
        print(val)
    }

    map_a = Map<i32, i32>{}
    loop key, val := map_a {
        print(key, val)
    }

    loop i := range(1, 10, 1) {
        print(i, get(list_a, i))
    }

    loop i := range(10, 1, 2) {
        print(i, get(list_a, i))
    }
}
