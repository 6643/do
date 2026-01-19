_start() {

    cx = Context {
        id: 1
    }

    a = do {
        id = get(cx, .id)
        if id == 1 {=> true}
        => login(cx, id, "tocken")
    }

    set_timeout(a, 1000)

    cancel(a)
    cancel(a, b, c)

    retry(a)
    retry(a, b, c)



    suspend
    resume
 
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

    => false
}


Context {
    id u32
}

 