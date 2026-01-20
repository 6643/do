// Text Test
malloc(size i32) -> i32 { 0 }

len(s Text) -> i32 {
    get(s, 1)
}

test_text() {
    s = "Hello World";
    l = len(s);
    l
}

test_text();
