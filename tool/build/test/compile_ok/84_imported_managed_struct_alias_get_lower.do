Profile = @lib("~/test.box.do", Box)
make_profile = @lib("~/test.box.do", make_box)

start() {
    profile Profile = make_profile()
    value [u8] = @get(profile, .value)
    return
}
