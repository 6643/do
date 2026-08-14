choose(flag bool, left text, right text) -> text {
    if flag {
        return left
    }
    return right
}

start() {}
