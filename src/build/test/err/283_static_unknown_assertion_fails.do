test "static unknown assertion fails" {
    if @eq(@div(1, 0), 0) return
}
