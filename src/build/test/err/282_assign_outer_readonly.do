test "assign outer readonly" {
    _limit i32 = 1
    {
        _limit = 2
    }
}
