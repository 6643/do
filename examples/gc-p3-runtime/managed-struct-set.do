Box {
    value [u8]
}

update(box Box) -> Box {
    return @set(box, .value, @set(@get(box, .value), 0, 65))
}

start() {}
