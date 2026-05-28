Text = @/text.do/Text
List = @/list.do/List
list_put = @/list.do/put

JsonError = InvalidEscape | UnterminatedEscape

_quote u8 = 34
_backslash u8 = 92
_newline u8 = 10
_carriage u8 = 13
_tab u8 = 9

escape(text Text) -> Text {
    out List<u8> = List<u8>{}
    i usize = 0
    loop {
        if eq(i, len(text)) return get(out, .items)
        ch u8 = at(text, i)
        if eq(ch, _quote) {
            out = list_put(out, _backslash)
            out = list_put(out, _quote)
        } else if eq(ch, _backslash) {
            out = list_put(out, _backslash)
            out = list_put(out, _backslash)
        } else if eq(ch, _newline) {
            out = list_put(out, _backslash)
            out = list_put(out, 110)
        } else if eq(ch, _carriage) {
            out = list_put(out, _backslash)
            out = list_put(out, 114)
        } else if eq(ch, _tab) {
            out = list_put(out, _backslash)
            out = list_put(out, 116)
        } else {
            out = list_put(out, ch)
        }
        i = add(i, 1)
    }
}

quote(text Text) -> Text {
    out List<u8> = List<u8>{}
    out = list_put(out, _quote)
    escaped Text = escape(text)
    loop ch, _ = escaped {
        out = list_put(out, ch)
    }
    out = list_put(out, _quote)
    return get(out, .items)
}

unescape(text Text) -> Text | JsonError {
    out List<u8> = List<u8>{}
    i usize = 0
    loop {
        if eq(i, len(text)) return get(out, .items)
        ch u8 = at(text, i)
        if ne(ch, _backslash) {
            out = list_put(out, ch)
            i = add(i, 1)
            continue
        }
        if eq(add(i, 1), len(text)) return UnterminatedEscape
        next u8 = at(text, add(i, 1))
        if eq(next, _quote) {
            out = list_put(out, _quote)
        } else if eq(next, _backslash) {
            out = list_put(out, _backslash)
        } else if eq(next, 110) {
            out = list_put(out, _newline)
        } else if eq(next, 114) {
            out = list_put(out, _carriage)
        } else if eq(next, 116) {
            out = list_put(out, _tab)
        } else {
            return InvalidEscape
        }
        i = add(i, 2)
    }
}
