cancel_pending = @lib("~/fixture.cancel_lowering.do", cancel_pending)

start() {
    cancel_pending()
}
