InternalUser = @lib("./fixture.type_profile.do", Profile)

.InternalUser = User | nil

User {
    name [u8]
}

test "private type import alias conflict" {
    return
}
