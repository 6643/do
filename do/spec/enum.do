HttpStatus = Continue(100, "Continue") | Ok(200) | Err(Text)
Shape = Circle(r f64) | Square(w f64, h f64)

test "enum match" {
    s = Ok(200)
    
    msg = match s {
        Ok(code): "Success"
        Err(e):   e
        _:        "Unknown"
    }

    area = match Circle(10.5) {
        Circle(r): mul(3.14, r, r)
        Square(w, h): mul(w, h)
    }

    c = Circle(10.0)
    if Circle(r) := c {
        print("Radius: ${r}")
    }
}