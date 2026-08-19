test "compiled text branch preserves selected value" {
    left text = "left"
    right text = "right"
    selected text = left
    if @eq(selected, "left") return
}
