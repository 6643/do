# G5a `[u8]` `@put` Design

**Status:** approved bounded migration slice. This document admits one parsed
GC lowering shape; it does not change the default backend.

## Goal

Lower the smallest missing byte-list append operation through the parsed
synchronous GC entry:

```do
append_byte(input [u8], value u8) -> [u8] {
    return @put(input, value)
}
```

`@put` returns a new logical list value. The source list remains observable and
unchanged, including when the source is empty. The new backing is allowed to
use `array.set` after the copy because the backing is private to the result.

## Fixed Boundary

Admitted only when all of these are true:

- the program is a complete synchronous GC program already accepted by
  `emit_gc_wat_for_supported_program`;
- the receiver is a local of exactly `[u8]`;
- exactly one value argument is supplied and it is compatible with `u8`;
- the result is exactly `[u8]`;
- there are no module imports, generic functions, async operations, resources,
  host calls, or multi-result functions.

The following remain rejected in this slice:

- `@put(input, value0, value1)` and any other multi-value form;
- `@put(input, ...values)` spread form;
- non-`[u8]` receivers or non-`u8` values;
- nested/non-literal producer expressions that the existing GC emitter does
  not already admit;
- any new public `ref<T>`, `own<T>`, `borrow<T>`, `Result<T, E>`, or `Option<T>`
  syntax.

## Lowering Contract

For a source list with runtime length `n`, the GC emitter must produce the
equivalent of:

```wat
;; source is a non-null [u8] reference
local.get $source
ref.as_non_null
array.len
local.set $length

local.get $length
i32.const 1
i32.add
array.new_default $do_bytes
local.set $next

local.get $next
i32.const 0
local.get $source
ref.as_non_null
i32.const 0
local.get $length
array.copy $do_bytes $do_bytes

local.get $next
local.get $length
;; emit the one checked u8 value
array.set $do_bytes
local.get $next
```

The source is never written. `ref.as_non_null` preserves the existing trap
behavior for a nil list receiver. The temporary locals must be renamed when a
source binding already uses their default names.

## Verification Gate

The focused gate must prove:

1. parsed source emits a GC array allocation sized `n + 1`, a runtime-length
   copy, and one `array.set`, with no `__arc_` symbol;
2. a probe appends to an empty list and a non-empty list, observes the new
   value, and verifies the original list remains unchanged;
3. two calls produce distinct result arrays while the first result stays live;
4. multi-value, spread, and non-`u8` neighboring shapes fail before WAT;
5. existing GC, default compiler, and full regression gates remain green.

This is a G5a capability slice only. G5b must later compare its source
observables against the default ARC path, and G5c remains blocked until the
complete-program equivalence matrix is green.

## Rollback

Remove the parsed `@put` matcher, focused tests, and probe entry changes. The
existing parsed `@set` and list-literal slices remain intact, and the default
ARC compiler path is unaffected by this rollback.
