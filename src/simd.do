#T = i32 | i64 | f32 | f64
Vec2 {
    x T
    y T
}

#T = i32 | i64 | f32 | f64
Vec4 {
    x T
    y T
    z T
    w T
}

#T = i32 | i64 | f32 | f64
vec2(x T, y T) -> Vec2<T> {
    return Vec2<T>{x = x, y = y}
}

#T = i32 | i64 | f32 | f64
vec4(x T, y T, z T, w T) -> Vec4<T> {
    return Vec4<T>{x = x, y = y, z = z, w = w}
}

#T = i32 | i64 | f32 | f64
splat2(v T) -> Vec2<T> {
    return Vec2<T>{x = v, y = v}
}

#T = i32 | i64 | f32 | f64
splat4(v T) -> Vec4<T> {
    return Vec4<T>{x = v, y = v, z = v, w = v}
}

#T = i32 | i64 | f32 | f64
add2(a Vec2<T>, b Vec2<T>) -> Vec2<T> {
    return Vec2<T>{
        x = add(get(a, .x), get(b, .x)),
        y = add(get(a, .y), get(b, .y)),
    }
}

#T = i32 | i64 | f32 | f64
sub2(a Vec2<T>, b Vec2<T>) -> Vec2<T> {
    return Vec2<T>{
        x = sub(get(a, .x), get(b, .x)),
        y = sub(get(a, .y), get(b, .y)),
    }
}

#T = i32 | i64 | f32 | f64
mul2(a Vec2<T>, b Vec2<T>) -> Vec2<T> {
    return Vec2<T>{
        x = mul(get(a, .x), get(b, .x)),
        y = mul(get(a, .y), get(b, .y)),
    }
}

#T = i32 | i64 | f32 | f64
dot2(a Vec2<T>, b Vec2<T>) -> T {
    return add(
        mul(get(a, .x), get(b, .x)),
        mul(get(a, .y), get(b, .y)),
    )
}

#T = i32 | i64 | f32 | f64
add4(a Vec4<T>, b Vec4<T>) -> Vec4<T> {
    return Vec4<T>{
        x = add(get(a, .x), get(b, .x)),
        y = add(get(a, .y), get(b, .y)),
        z = add(get(a, .z), get(b, .z)),
        w = add(get(a, .w), get(b, .w)),
    }
}

#T = i32 | i64 | f32 | f64
mul4(a Vec4<T>, b Vec4<T>) -> Vec4<T> {
    return Vec4<T>{
        x = mul(get(a, .x), get(b, .x)),
        y = mul(get(a, .y), get(b, .y)),
        z = mul(get(a, .z), get(b, .z)),
        w = mul(get(a, .w), get(b, .w)),
    }
}

#T = i32 | i64 | f32 | f64
dot4(a Vec4<T>, b Vec4<T>) -> T {
    return add(
        mul(get(a, .x), get(b, .x)),
        mul(get(a, .y), get(b, .y)),
        mul(get(a, .z), get(b, .z)),
        mul(get(a, .w), get(b, .w)),
    )
}
