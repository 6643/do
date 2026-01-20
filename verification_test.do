test_tuple() {
    t = set(Tuple<i32, f64>, [100, 3.14]);
    v0 = get(t, 0);
    v1 = get(t, 1);
}

test_array() {
    arr = set(Array<i32, 3>, [10, 20, 30]);
    v = get(arr, 1); // Should be 20
}

test_intrinsics(n i32) {
    size = mem_size();
    c = ctz(n);
    unreachable();
}

test_destructuring() {
    t = set(Tuple<i32, i32>, [1, 2]);
    (a, b) = t;
}

test_text() {
    s = "Hello do!";
    // length calculation would be get(s, 1) in our internal layout
    len = get(s, 1);
}
