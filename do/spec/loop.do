test "loops and labels" {
    count = 0
    loop {
        count = add(count, 1)
        if eq(count, 5) {
            // continue 当前循环
            <- 
        }
        if eq(count, 10) {
            // break 当前循环
            -> 
        }
    }

    total = 0
    loop { #outer
        loop {
            total = add(total, 1)
            if gt(total, 100) {
                // break 到标签 #outer
                -> #outer
            }else{
                // continue 到标签 #outer
                #outer <- 
            }
        }
    }
}