Dir = @lib("dir.do", Dir)
DirError = @lib("dir.do", DirError)
create_dir_at = @lib("dir.do", create_dir_at)
remove_dir_at = @lib("dir.do", remove_dir_at)

create_dir_sample(parent Dir) -> DirError | nil {
    path text = "data"
    return create_dir_at(parent, path)
}

remove_dir_sample(parent Dir) -> DirError | nil {
    path text = "data"
    return remove_dir_at(parent, path)
}

start() {
    return
}
