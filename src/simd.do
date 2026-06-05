Vec2I32 {
    x i32
    y i32
}

Vec4I32 {
    x i32
    y i32
    z i32
    w i32
}

vec2_i32(x i32, y i32) -> Vec2I32 {
    return Vec2I32{x = x, y = y}
}

vec4_i32(x i32, y i32, z i32, w i32) -> Vec4I32 {
    return Vec4I32{x = x, y = y, z = z, w = w}
}

splat2_i32(v i32) -> Vec2I32 {
    return Vec2I32{x = v, y = v}
}

splat4_i32(v i32) -> Vec4I32 {
    return Vec4I32{x = v, y = v, z = v, w = v}
}

add2_i32(a Vec2I32, b Vec2I32) -> Vec2I32 {
    return Vec2I32{x = add(get(a, .x), get(b, .x)), y = add(get(a, .y), get(b, .y))}
}

sub2_i32(a Vec2I32, b Vec2I32) -> Vec2I32 {
    return Vec2I32{x = sub(get(a, .x), get(b, .x)), y = sub(get(a, .y), get(b, .y))}
}

mul2_i32(a Vec2I32, b Vec2I32) -> Vec2I32 {
    return Vec2I32{x = mul(get(a, .x), get(b, .x)), y = mul(get(a, .y), get(b, .y))}
}

dot2_i32(a Vec2I32, b Vec2I32) -> i32 {
    return add(mul(get(a, .x), get(b, .x)), mul(get(a, .y), get(b, .y)))
}

add4_i32(a Vec4I32, b Vec4I32) -> Vec4I32 {
    return Vec4I32{x = add(get(a, .x), get(b, .x)), y = add(get(a, .y), get(b, .y)), z = add(get(a, .z), get(b, .z)), w = add(get(a, .w), get(b, .w))}
}

mul4_i32(a Vec4I32, b Vec4I32) -> Vec4I32 {
    return Vec4I32{x = mul(get(a, .x), get(b, .x)), y = mul(get(a, .y), get(b, .y)), z = mul(get(a, .z), get(b, .z)), w = mul(get(a, .w), get(b, .w))}
}

dot4_i32(a Vec4I32, b Vec4I32) -> i32 {
    return add(mul(get(a, .x), get(b, .x)), mul(get(a, .y), get(b, .y)), mul(get(a, .z), get(b, .z)), mul(get(a, .w), get(b, .w)))
}

Vec2I64 {
    x i64
    y i64
}

Vec4I64 {
    x i64
    y i64
    z i64
    w i64
}

vec2_i64(x i64, y i64) -> Vec2I64 {
    return Vec2I64{x = x, y = y}
}

vec4_i64(x i64, y i64, z i64, w i64) -> Vec4I64 {
    return Vec4I64{x = x, y = y, z = z, w = w}
}

splat2_i64(v i64) -> Vec2I64 {
    return Vec2I64{x = v, y = v}
}

splat4_i64(v i64) -> Vec4I64 {
    return Vec4I64{x = v, y = v, z = v, w = v}
}

add2_i64(a Vec2I64, b Vec2I64) -> Vec2I64 {
    return Vec2I64{x = add(get(a, .x), get(b, .x)), y = add(get(a, .y), get(b, .y))}
}

sub2_i64(a Vec2I64, b Vec2I64) -> Vec2I64 {
    return Vec2I64{x = sub(get(a, .x), get(b, .x)), y = sub(get(a, .y), get(b, .y))}
}

mul2_i64(a Vec2I64, b Vec2I64) -> Vec2I64 {
    return Vec2I64{x = mul(get(a, .x), get(b, .x)), y = mul(get(a, .y), get(b, .y))}
}

dot2_i64(a Vec2I64, b Vec2I64) -> i64 {
    return add(mul(get(a, .x), get(b, .x)), mul(get(a, .y), get(b, .y)))
}

add4_i64(a Vec4I64, b Vec4I64) -> Vec4I64 {
    return Vec4I64{x = add(get(a, .x), get(b, .x)), y = add(get(a, .y), get(b, .y)), z = add(get(a, .z), get(b, .z)), w = add(get(a, .w), get(b, .w))}
}

mul4_i64(a Vec4I64, b Vec4I64) -> Vec4I64 {
    return Vec4I64{x = mul(get(a, .x), get(b, .x)), y = mul(get(a, .y), get(b, .y)), z = mul(get(a, .z), get(b, .z)), w = mul(get(a, .w), get(b, .w))}
}

dot4_i64(a Vec4I64, b Vec4I64) -> i64 {
    return add(mul(get(a, .x), get(b, .x)), mul(get(a, .y), get(b, .y)), mul(get(a, .z), get(b, .z)), mul(get(a, .w), get(b, .w)))
}

Vec2F32 {
    x f32
    y f32
}

Vec4F32 {
    x f32
    y f32
    z f32
    w f32
}

vec2_f32(x f32, y f32) -> Vec2F32 {
    return Vec2F32{x = x, y = y}
}

vec4_f32(x f32, y f32, z f32, w f32) -> Vec4F32 {
    return Vec4F32{x = x, y = y, z = z, w = w}
}

splat2_f32(v f32) -> Vec2F32 {
    return Vec2F32{x = v, y = v}
}

splat4_f32(v f32) -> Vec4F32 {
    return Vec4F32{x = v, y = v, z = v, w = v}
}

add2_f32(a Vec2F32, b Vec2F32) -> Vec2F32 {
    return Vec2F32{x = add(get(a, .x), get(b, .x)), y = add(get(a, .y), get(b, .y))}
}

sub2_f32(a Vec2F32, b Vec2F32) -> Vec2F32 {
    return Vec2F32{x = sub(get(a, .x), get(b, .x)), y = sub(get(a, .y), get(b, .y))}
}

mul2_f32(a Vec2F32, b Vec2F32) -> Vec2F32 {
    return Vec2F32{x = mul(get(a, .x), get(b, .x)), y = mul(get(a, .y), get(b, .y))}
}

dot2_f32(a Vec2F32, b Vec2F32) -> f32 {
    return add(mul(get(a, .x), get(b, .x)), mul(get(a, .y), get(b, .y)))
}

add4_f32(a Vec4F32, b Vec4F32) -> Vec4F32 {
    return Vec4F32{x = add(get(a, .x), get(b, .x)), y = add(get(a, .y), get(b, .y)), z = add(get(a, .z), get(b, .z)), w = add(get(a, .w), get(b, .w))}
}

mul4_f32(a Vec4F32, b Vec4F32) -> Vec4F32 {
    return Vec4F32{x = mul(get(a, .x), get(b, .x)), y = mul(get(a, .y), get(b, .y)), z = mul(get(a, .z), get(b, .z)), w = mul(get(a, .w), get(b, .w))}
}

dot4_f32(a Vec4F32, b Vec4F32) -> f32 {
    return add(mul(get(a, .x), get(b, .x)), mul(get(a, .y), get(b, .y)), mul(get(a, .z), get(b, .z)), mul(get(a, .w), get(b, .w)))
}

Vec2F64 {
    x f64
    y f64
}

Vec4F64 {
    x f64
    y f64
    z f64
    w f64
}

vec2_f64(x f64, y f64) -> Vec2F64 {
    return Vec2F64{x = x, y = y}
}

vec4_f64(x f64, y f64, z f64, w f64) -> Vec4F64 {
    return Vec4F64{x = x, y = y, z = z, w = w}
}

splat2_f64(v f64) -> Vec2F64 {
    return Vec2F64{x = v, y = v}
}

splat4_f64(v f64) -> Vec4F64 {
    return Vec4F64{x = v, y = v, z = v, w = v}
}

add2_f64(a Vec2F64, b Vec2F64) -> Vec2F64 {
    return Vec2F64{x = add(get(a, .x), get(b, .x)), y = add(get(a, .y), get(b, .y))}
}

sub2_f64(a Vec2F64, b Vec2F64) -> Vec2F64 {
    return Vec2F64{x = sub(get(a, .x), get(b, .x)), y = sub(get(a, .y), get(b, .y))}
}

mul2_f64(a Vec2F64, b Vec2F64) -> Vec2F64 {
    return Vec2F64{x = mul(get(a, .x), get(b, .x)), y = mul(get(a, .y), get(b, .y))}
}

dot2_f64(a Vec2F64, b Vec2F64) -> f64 {
    return add(mul(get(a, .x), get(b, .x)), mul(get(a, .y), get(b, .y)))
}

add4_f64(a Vec4F64, b Vec4F64) -> Vec4F64 {
    return Vec4F64{x = add(get(a, .x), get(b, .x)), y = add(get(a, .y), get(b, .y)), z = add(get(a, .z), get(b, .z)), w = add(get(a, .w), get(b, .w))}
}

mul4_f64(a Vec4F64, b Vec4F64) -> Vec4F64 {
    return Vec4F64{x = mul(get(a, .x), get(b, .x)), y = mul(get(a, .y), get(b, .y)), z = mul(get(a, .z), get(b, .z)), w = mul(get(a, .w), get(b, .w))}
}

dot4_f64(a Vec4F64, b Vec4F64) -> f64 {
    return add(mul(get(a, .x), get(b, .x)), mul(get(a, .y), get(b, .y)), mul(get(a, .z), get(b, .z)), mul(get(a, .w), get(b, .w)))
}
