path_basename = @lib("path.do", basename)
path_dirname = @lib("path.do", dirname)
path_extname = @lib("path.do", extname)
path_is_absolute = @lib("path.do", is_absolute)
path_is_empty = @lib("path.do", is_empty)
path_join = @lib("path.do", join)

test "path helpers" {
    ok bool = true
    ok = @and(ok, path_is_absolute("/tmp/a.txt"))
    ok = @and(ok, @not(path_is_absolute("tmp/a.txt")))
    ok = @and(ok, path_is_empty(""))
    ok = @and(ok, @not(path_is_empty("a")))
    ok = @and(ok, @eq(path_join("/tmp", "a", "b.txt"), "/tmp/a/b.txt"))
    ok = @and(ok, @eq(path_join("/tmp/", "", "a.txt"), "/tmp/a.txt"))
    ok = @and(ok, @eq(path_basename("/tmp/a.txt"), "a.txt"))
    ok = @and(ok, @eq(path_basename("/tmp/"), ""))
    ok = @and(ok, @eq(path_dirname("/tmp/a.txt"), "/tmp"))
    ok = @and(ok, @eq(path_dirname("a.txt"), "."))
    ok = @and(ok, @eq(path_dirname("/"), "/"))
    ok = @and(ok, @eq(path_extname("/tmp/a.txt"), ".txt"))
    ok = @and(ok, @eq(path_extname("README"), ""))
    if ok return
}
