_start() {
    cx = set(Context, .{.id: 1})

    a =  do(login, cx, 1, "tocken")
    b =  do(login, cx, 2, "tocken")
    c =  do(login, cx, 3, "tocken")

    a =  do(login, .{cx, 1, "tocken"})
    b =  do(login, .{cx, 2, "tocken"})
    c =  do(login, .{cx, 3, "tocken"})

    a = do login(cx, 1, "tocken")
    b = do login(cx, 2, "tocken")
    c = do login(cx, 3, "tocken")

    set_timeout(a, 1000)
    set_timeout(b, 2000)
    set_timeout(c, 3000)

    cancel(a)
    cancel(a, b, c)

    retry(a)
    retry(a, b, c)



    //suspend
    //resume
 
    cccc = done(a)
    if cccc {
        print("login success")
    }else{
        print("login failed")
    }

    dddd = any_done(a, b, c)
    [e, f, g] = all_done(a, b, c)

 
}   

login(cx Context, id u32, t text) bool {
    id = get(cx, .id)
    if eq(id, 1) {=> true}
    => false
}


Context {
    id u32
}

 