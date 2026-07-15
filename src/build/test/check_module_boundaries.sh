#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_DIR="$ROOT/src/build"
fail=0

while IFS= read -r path; do
    echo "old compiler module name remains: $path" >&2
    fail=1
done < <(find "$BUILD_DIR" -maxdepth 1 -type f \( -name 'gen_*.zig' -o -name 'sema_func_*.zig' \) | sort)

for facade in "$BUILD_DIR/gen_collect.zig" "$BUILD_DIR/sema_util.zig"; do
    if [[ -e "$facade" ]]; then
        echo "facade remains: $facade" >&2
        fail=1
    fi
done

collect_files=()
while IFS= read -r path; do
    collect_files+=("$path")
done < <(find "$BUILD_DIR" -maxdepth 1 -type f \( -name 'codegen_collect_*.zig' -o -name 'codegen_collect_body.zig' \) | sort)
if ((${#collect_files[@]} > 0)); then
    while IFS= read -r match; do
        echo "$match" >&2
        fail=1
    done < <(rg -n '@import\("codegen_emit_[^"]+\.zig"\)' "${collect_files[@]}" || true)
fi

wat_files=()
while IFS= read -r path; do
    wat_files+=("$path")
done < <(find "$BUILD_DIR" -maxdepth 1 -type f \( -name 'wat_*.zig' -o -name 'runtime_*' \) | sort)
if ((${#wat_files[@]} > 0)); then
    while IFS= read -r match; do
        echo "$match" >&2
        fail=1
    done < <(rg -n '@import\("codegen_pipeline\.zig"\)' "${wat_files[@]}" || true)
fi

if rg -n '@import\("codegen_emit_wasi\.zig"\)' "$BUILD_DIR/codegen_storage_layout.zig"; then
    echo "storage layout must not import WASI emitter" >&2
    fail=1
fi

if rg -n '^pub const .* = codegen_(generics|storage_layout|emit_wasi)\.' "$BUILD_DIR/codegen_pipeline.zig"; then
    echo "codegen pipeline must not re-export leaf generic/storage/WASI helpers" >&2
    fail=1
fi

exit "$fail"
