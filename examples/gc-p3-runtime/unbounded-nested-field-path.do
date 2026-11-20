Level12 {
    payload [u8]
    tag i32
}

Level11 {
    child Level12
    tag i32
}

Level10 {
    child Level11
    tag i32
}

Level9 {
    child Level10
    tag i32
}

Level8 {
    child Level9
    tag i32
}

Level7 {
    child Level8
    tag i32
}

Level6 {
    child Level7
    tag i32
}

Level5 {
    child Level6
    tag i32
}

Level4 {
    child Level5
    tag i32
}

Level3 {
    child Level4
    tag i32
}

Level2 {
    child Level3
    tag i32
}

Level1 {
    child Level2
    tag i32
}

Level0 {
    child Level1
    tag i32
}

read_tag(root Level0) -> i32 {
    return @get(root, .child, .child, .child, .child, .child, .child, .child, .child, .child, .child, .child, .child, .tag)
}

update(root Level0) -> Level0 {
    return @set(root, .child, .child, .child, .child, .child, .child, .child, .child, .child, .child, .child, .child, .tag, 13)
}

start() {}
