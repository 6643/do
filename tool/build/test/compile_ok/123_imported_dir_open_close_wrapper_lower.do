Dir = @lib("dir.do", Dir)
DirError = @lib("dir.do", DirError)
open_dir_at = @lib("dir.do", open_dir_at)
close_dir = @lib("dir.do", close_dir)

open_dir_sample(parent Dir) -> Dir | DirError {
    path text = "data"
    return open_dir_at(parent, path)
}

close_dir_sample(dir Dir) -> nil {
    close_dir(dir)
    return
}

start() {
    return
}
