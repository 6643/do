test "loops and labels" {
    count = 0
    loop {
        count = add(count, 1)
        if eq(count, 5) {
            <- // continue
        }
        if eq(count, 10) {
            -> // break
        }
    }

    total = 0
    loop { #outer
        loop {
            total = add(total, 1)
            if gt(total, 100) {
                -> outer
            }
        }
    }
}