#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECKER="$ROOT/src/build/test/check_gc_semantic_equivalence.sh"

if [[ ! -x "$CHECKER" ]]; then
    printf 'missing executable semantic equivalence checker: %s\n' "$CHECKER" >&2
    exit 1
fi

for row in list-set managed-struct-payload text-identity text-branch scalar-list-remaining scalar-list-put text-list-put payload-union generic-managed-identity; do
    if ! rg -q "^${row}[[:space:]]" "$CHECKER"; then
        printf 'missing equivalence row: %s\n' "$row" >&2
        exit 1
    fi
done

if rg -q '^[^#[:space:]][^[:space:]]*[[:space:]]+pending([[:space:]]|$)' "$CHECKER"; then
    printf 'equivalence matrix must not leave an admitted row pending\n' >&2
    exit 1
fi

if ! rg -q 'run_compiled_fixture' "$CHECKER" || ! rg -q 'run_gc_probe' "$CHECKER"; then
    printf 'checker must execute normal and GC paths separately\n' >&2
    exit 1
fi

if rg -q '__arc_|WAT|wat.*identity|allocation identity' "$CHECKER"; then
    printf 'checker must not compare backend symbols, WAT text, or allocation identity\n' >&2
    exit 1
fi

printf 'GC semantic equivalence checker contract passed\n'
