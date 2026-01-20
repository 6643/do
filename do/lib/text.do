// Text Library
// Text layout: Header(8) + Ptr(4) + Len(4)

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
    
    // 1. Allocate raw data buffer
    data = malloc(new_len);
    
    // 2. Copy first string
    p1 = ptr(s1);
    i = 0;
    loop {
        if (i == l1) => break;
        // Use i32_store/load for byte access (needs refinement for true u8)
        // For now, we'll treat each char as i32 for simplicity in test
        val = i32_load(p1 + i * 4);
        i32_store(data + i * 4, val);
        i = i + 1;
    }
    
    // 3. Copy second string
    p2 = ptr(s2);
    j = 0;
    loop {
        if (j == l2) => break;
        val = i32_load(p2 + j * 4);
        i32_store(data + (l1 + j) * 4, val);
        j = j + 1;
    }
    
    // 4. Return new managed Text object
    Text(data, new_len)
}
