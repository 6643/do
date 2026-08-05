#T
Pair {
    left T
    right T
}

#T
Box {
    value Pair<T>
}

accept(box Box<i32>) -> i32 {
    return 0
}
