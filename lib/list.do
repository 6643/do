ListError = OutOfBounds

#T
List {
    .len usize = 0
    .items [T] = storage()
}

#T
empty() -> List<T> {
    return List<T>{}
}

#T
len(xs List<T>) -> usize {
    return get(xs, .len)
}

#T
items(xs List<T>) -> [T] {
    return get(xs, .items)
}

#T
at(xs List<T>, i usize) -> T {
    return at(get(xs, .items), i)
}

#T
get(xs List<T>, i usize) -> T | nil {
    if ge(i, len(xs)) return nil
    return at(xs, i)
}

#T
put(xs List<T>, value T) -> List<T> {
    data [T] = get(xs, .items)
    next_data [T] = put(data, value)
    return List<T>{
        len = add(len(xs), 1),
        items = next_data,
    }
}

#T
set(xs List<T>, i usize, value T) -> List<T> | ListError {
    if ge(i, len(xs)) return OutOfBounds
    data [T] = get(xs, .items)
    next_data [T] = set(data, i, value)
    return List<T>{
        len = len(xs),
        items = next_data,
    }
}

#T
clear(_ List<T>) -> List<T> {
    return List<T>{}
}
