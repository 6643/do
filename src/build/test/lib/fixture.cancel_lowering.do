cancel_pending() -> nil {
    pending Future<i32> = nil
    @cancel(pending)
}
