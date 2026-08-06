completion = @lib("./wit/do_bindgen_probe__api__probe.do", completion)

run() -> nil {
    ready Future<u32> = completion()
    value u32 = @await(ready)
    _ = value

    pending Future<u32> = completion()
    @cancel(pending)
}
