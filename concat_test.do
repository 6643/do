// Concat Test
// No manual declarations needed! Prelude is active.

test_concat() {
    s1 = "Hello";
    s2 = " World";
    s3 = concat(s1, s2);
    
    l = len(s3);
    l
}

test_concat();
