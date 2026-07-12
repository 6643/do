// G6.1 / P3: std preopen_directories is thin host forward to [Tuple<Dir,text>].
preopen_directories = @lib("dir.do", preopen_directories)
Dir = @lib("dir.do", Dir)
close_dir = @lib("dir.do", close_dir)

start() {
    roots [Tuple<Dir, text>] = preopen_directories()
    _ = roots
}
