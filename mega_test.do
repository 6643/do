// Mega End-to-End Test
malloc(size i32) -> i32 {
    // Dummy malloc for testing logic generation
    0
}

len(s Text) -> i32 {
    get(s, 1)
}

ptr(s Text) -> i32 {
    get(s, 0)
}

concat(s1 Text, s2 Text) -> Text {
    l1 = len(s1);
    l2 = len(s2);
    new_len = l1 + l2;
    data = malloc(new_len);
    
    // Simple copy loop
    i = 0;
    loop {
        if (i == l1) => break;
        i32_store(data + i * 4, i32_load(ptr(s1) + i * 4));
        i = i + 1;
    }
    
    j = 0;
    loop {
        if (j == l2) => break;
        i32_store(data + (l1 + j) * 4, i32_load(ptr(s2) + j * 4));
        j = j + 1;
    }
    
    Text(data, new_len)
}

test_main() {
    s1 = "Hello";
    s2 = " World";
    s3 = concat(s1, s2);
    l = len(s3);
    l
}

test_main();
