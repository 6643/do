Utf8Error = @utf8.do/Utf8Error
BytesError = @bytes.do/BytesError
utf8_count = @utf8.do/count
utf8_is_valid = @utf8.do/is_valid
utf8_validate = @utf8.do/validate
bytes_contains = @bytes.do/contains
bytes_concat = @bytes.do/concat
bytes_copy = @bytes.do/copy
bytes_drop = @bytes.do/drop
bytes_drop_or = @bytes.do/drop_or
bytes_ends_with = @bytes.do/ends_with
bytes_first = @bytes.do/first
bytes_first_or = @bytes.do/first_or
bytes_index_of = @bytes.do/index_of
bytes_last = @bytes.do/last
bytes_last_or = @bytes.do/last_or
bytes_last_index_of = @bytes.do/last_index_of
bytes_replace = @bytes.do/replace
bytes_repeat_byte = @bytes.do/repeat_byte
bytes_slice_or = @bytes.do/slice_or
bytes_starts_with = @bytes.do/starts_with
bytes_take = @bytes.do/take
bytes_take_or = @bytes.do/take_or
bytes_trim_left_byte = @bytes.do/trim_left_byte
bytes_trim_byte = @bytes.do/trim_byte
bytes_trim_right_byte = @bytes.do/trim_right_byte

is_empty(s [u8]) -> bool {
    return eq(len(s), 0)
}

is_valid_utf8(s [u8]) -> bool {
    return utf8_is_valid(s)
}

validate_utf8(s [u8]) -> Utf8Error | nil {
    return utf8_validate(s)
}

count_utf8(s [u8]) -> usize | Utf8Error {
    return utf8_count(s)
}

copy(s [u8]) -> [u8] {
    return bytes_copy(s)
}

concat(a [u8], b [u8], rest ...[u8]) -> [u8] {
    return bytes_concat(a, b, ...rest)
}

repeat_byte(value u8, count usize) -> [u8] {
    return bytes_repeat_byte(value, count)
}

starts_with(s [u8], prefix [u8]) -> bool {
    return bytes_starts_with(s, prefix)
}

ends_with(s [u8], suffix [u8]) -> bool {
    return bytes_ends_with(s, suffix)
}

contains(s [u8], needle [u8]) -> bool {
    return bytes_contains(s, needle)
}

index_of(s [u8], needle [u8]) -> usize | nil {
    return bytes_index_of(s, needle)
}

last_index_of(s [u8], needle [u8]) -> usize | nil {
    return bytes_last_index_of(s, needle)
}

slice_or(s [u8], from usize, end usize, fallback [u8]) -> [u8], bool {
    return bytes_slice_or(s, from, end, fallback)
}

take(s [u8], count usize) -> [u8] | BytesError {
    return bytes_take(s, count)
}

take_or(s [u8], count usize, fallback [u8]) -> [u8], bool {
    return bytes_take_or(s, count, fallback)
}

drop(s [u8], count usize) -> [u8] | BytesError {
    return bytes_drop(s, count)
}

drop_or(s [u8], count usize, fallback [u8]) -> [u8], bool {
    return bytes_drop_or(s, count, fallback)
}

first(s [u8]) -> u8 {
    return bytes_first(s)
}

first_or(s [u8], fallback u8) -> u8, bool {
    return bytes_first_or(s, fallback)
}

last(s [u8]) -> u8 {
    return bytes_last(s)
}

last_or(s [u8], fallback u8) -> u8, bool {
    return bytes_last_or(s, fallback)
}

trim_left_byte(s [u8], value u8) -> [u8] {
    return bytes_trim_left_byte(s, value)
}

trim_byte(s [u8], value u8) -> [u8] {
    return bytes_trim_byte(s, value)
}

trim_right_byte(s [u8], value u8) -> [u8] {
    return bytes_trim_right_byte(s, value)
}

replace(s [u8], needle [u8], replacement [u8]) -> [u8] {
    return bytes_replace(s, needle, replacement)
}
