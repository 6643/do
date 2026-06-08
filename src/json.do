List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
list_add = @lib("list.do", list_add)
list_items = @lib("list.do", items)

JsonError error = InvalidEscape | UnterminatedEscape

_quote u8 = 34
_backslash u8 = 92
_newline u8 = 10
_carriage u8 = 13
_tab u8 = 9

escape(bytes [u8]) -> [u8] {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    i usize = 0
    loop {
        if @eq(i, @len(bytes)) return list_items(out)
        ch u8 = @get(bytes, i)
        if @eq(ch, _quote) {
            out = list_add(out, _backslash)
            out = list_add(out, _quote)
        } else if @eq(ch, _backslash) {
            out = list_add(out, _backslash)
            out = list_add(out, _backslash)
        } else if @eq(ch, _newline) {
            out = list_add(out, _backslash)
            out = list_add(out, 110)
        } else if @eq(ch, _carriage) {
            out = list_add(out, _backslash)
            out = list_add(out, 114)
        } else if @eq(ch, _tab) {
            out = list_add(out, _backslash)
            out = list_add(out, 116)
        } else {
            out = list_add(out, ch)
        }
        i = @add(i, 1)
    }
}

quote(bytes [u8]) -> [u8] {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    out = list_add(out, _quote)
    escaped [u8] = escape(bytes)
    loop byte, _ = escaped {
        out = list_add(out, byte)
    }
    out = list_add(out, _quote)
    return list_items(out)
}

unescape(bytes [u8]) -> [u8] | JsonError {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    i usize = 0
    loop {
        if @eq(i, @len(bytes)) return list_items(out)
        ch u8 = @get(bytes, i)
        if @ne(ch, _backslash) {
            out = list_add(out, ch)
            i = @add(i, 1)
            continue
        }
        if @eq(@add(i, 1), @len(bytes)) return UnterminatedEscape
        next u8 = @get(bytes, @add(i, 1))
        if @eq(next, _quote) {
            out = list_add(out, _quote)
        } else if @eq(next, _backslash) {
            out = list_add(out, _backslash)
        } else if @eq(next, 110) {
            out = list_add(out, _newline)
        } else if @eq(next, 114) {
            out = list_add(out, _carriage)
        } else if @eq(next, 116) {
            out = list_add(out, _tab)
        } else {
            return InvalidEscape
        }
        i = @add(i, 2)
    }
}
