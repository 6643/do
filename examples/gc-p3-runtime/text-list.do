make_texts() -> [text] {
    first text = "a"
    texts [text] = .{first, "bc"}
    count usize = @len(texts)
    selected text = @get(texts, 0)
    loop item, index = texts {
        if @eq(index, 0) break
    }
    return texts
}

start() {}
