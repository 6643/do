test "unified and or not" {
    // 1. 逻辑运算 (bool)
    a = true
    b = false
    
    res_logic = and(a, not(b)) // true
    
    // 2. 位运算 (integers)
    x = 0b1010 // u8(10)
    y = 0b1100 // u8(12)
    
    res_bit = and(x, y) // 0b1000 (8)
    res_inv = not(x)    // 0b0101 (基于类型宽度的取反)

    // 3. 专用位运算
    z = xor(x, y)      // 0b0110 (6)
    val = shl(1, 4)    // 16
}

test "short-circuit logic" {
    cond = false
    
    // 如果是逻辑 and，若 cond 为 false，则后面的 print 不会执行
    // 这是由编译器在编译期根据参数类型生成的跳转控制流
    res = and(cond, print("this should not happen"))
}