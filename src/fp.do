#A
#B
#P = (A) -> B
apply(value A, p P) -> B {
    return p(value)
}

#A
#P = (A) -> nil
tap(value A, p P) -> A {
    p(value)
    return value
}

#A
#P = (A) -> A
repeat(value A, times usize, p P) -> A {
    out A = value
    i usize = 0
    loop {
        if ge(i, times) return out
        out = p(out)
        i = add(i, 1)
    }
}

#T
#U
#P = (T) -> U
map(xs [T], p P) -> [U] {
    out [U] = .{}
    loop value, _ = xs {
        out = put(out, p(value))
    }
    return out
}

#T
#E
#U
#P = (T, E) -> U
map(xs [T], env E, p P) -> [U] {
    out [U] = .{}
    loop value, _ = xs {
        out = put(out, p(value, env))
    }
    return out
}

#T
#P = (T) -> bool
filter(xs [T], p P) -> [T] {
    out [T] = .{}
    loop value, _ = xs {
        if p(value) {
            out = put(out, value)
        }
    }
    return out
}

#T
#E
#P = (T, E) -> bool
filter(xs [T], env E, p P) -> [T] {
    out [T] = .{}
    loop value, _ = xs {
        if p(value, env) {
            out = put(out, value)
        }
    }
    return out
}

#T
#U
#P = (U, T) -> U
fold(xs [T], init U, p P) -> U {
    out U = init
    loop value, _ = xs {
        out = p(out, value)
    }
    return out
}

#T
#P = (T, T) -> T
reduce(xs [T], fallback T, p P) -> T, bool {
    if eq(len(xs), 0) return fallback, false

    out T = get(xs, 0)
    i usize = 1
    loop {
        if ge(i, len(xs)) return out, true
        out = p(out, get(xs, i))
        i = add(i, 1)
    }
}

#T
#P = (T) -> bool
find(xs [T], fallback T, p P) -> T, bool {
    loop value, _ = xs {
        if p(value) return value, true
    }
    return fallback, false
}

#T
#E
#P = (T, E) -> bool
find(xs [T], fallback T, env E, p P) -> T, bool {
    loop value, _ = xs {
        if p(value, env) return value, true
    }
    return fallback, false
}

#T
#P = (T) -> bool
find_index(xs [T], p P) -> usize | nil {
    loop value, index = xs {
        if p(value) return index
    }
    return nil
}

#T
#E
#P = (T, E) -> bool
find_index(xs [T], env E, p P) -> usize | nil {
    loop value, index = xs {
        if p(value, env) return index
    }
    return nil
}

#T
#P = (T) -> bool
any(xs [T], p P) -> bool {
    loop value, _ = xs {
        if p(value) return true
    }
    return false
}

#T
#E
#P = (T, E) -> bool
any(xs [T], env E, p P) -> bool {
    loop value, _ = xs {
        if p(value, env) return true
    }
    return false
}

#T
#P = (T) -> bool
all(xs [T], p P) -> bool {
    loop value, _ = xs {
        if not(p(value)) return false
    }
    return true
}

#T
#E
#P = (T, E) -> bool
all(xs [T], env E, p P) -> bool {
    loop value, _ = xs {
        if not(p(value, env)) return false
    }
    return true
}

#T
#P = (T) -> bool
count(xs [T], p P) -> usize {
    out usize = 0
    loop value, _ = xs {
        if p(value) {
            out = add(out, 1)
        }
    }
    return out
}

#T
#E
#P = (T, E) -> bool
count(xs [T], env E, p P) -> usize {
    out usize = 0
    loop value, _ = xs {
        if p(value, env) {
            out = add(out, 1)
        }
    }
    return out
}

#A
#B
#P = (A) -> B
pipe(value A, p P) -> B {
    return apply(value, p)
}

#A
#B
#C
#P = (A) -> B
#Q = (B) -> C
pipe(value A, p P, q Q) -> C {
    return q(pipe(value, p))
}

#A
#B
#C
#D
#P = (A) -> B
#Q = (B) -> C
#R = (C) -> D
pipe(value A, p P, q Q, r R) -> D {
    return r(pipe(value, p, q))
}

#A
#B
#C
#D
#E
#P = (A) -> B
#Q = (B) -> C
#R = (C) -> D
#S = (D) -> E
pipe(value A, p P, q Q, r R, s S) -> E {
    return s(pipe(value, p, q, r))
}

#A
#B
#C
#D
#E
#F
#P = (A) -> B
#Q = (B) -> C
#R = (C) -> D
#S = (D) -> E
#U = (E) -> F
pipe(value A, p P, q Q, r R, s S, u U) -> F {
    return u(pipe(value, p, q, r, s))
}

#A
#B
#C
#D
#E
#F
#G
#P = (A) -> B
#Q = (B) -> C
#R = (C) -> D
#S = (D) -> E
#U = (E) -> F
#V = (F) -> G
pipe(value A, p P, q Q, r R, s S, u U, v V) -> G {
    return v(pipe(value, p, q, r, s, u))
}

#A
#B
#C
#D
#E
#F
#G
#H
#P = (A) -> B
#Q = (B) -> C
#R = (C) -> D
#S = (D) -> E
#U = (E) -> F
#V = (F) -> G
#W = (G) -> H
pipe(value A, p P, q Q, r R, s S, u U, v V, w W) -> H {
    return w(pipe(value, p, q, r, s, u, v))
}

#A
#B
#C
#D
#E
#F
#G
#H
#I
#P = (A) -> B
#Q = (B) -> C
#R = (C) -> D
#S = (D) -> E
#U = (E) -> F
#V = (F) -> G
#W = (G) -> H
#X = (H) -> I
pipe(value A, p P, q Q, r R, s S, u U, v V, w W, x X) -> I {
    return x(pipe(value, p, q, r, s, u, v, w))
}
