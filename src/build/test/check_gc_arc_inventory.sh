#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
inventory_path="${GC_ARC_INVENTORY:-$ROOT/doc/gc_arc_inventory.tsv}"
mode=pre_cutover

case "${1:-}" in
    "") ;;
    --post-cutover) mode=post_cutover ;;
    *)
        printf 'usage: %s [--post-cutover]\n' "${BASH_SOURCE[0]}" >&2
        exit 2
        ;;
esac

if [[ ! -f "$inventory_path" ]]; then
    printf 'missing ARC inventory: %s\n' "$inventory_path" >&2
    exit 2
fi

declare -a row_path=()
declare -a row_pattern=()
declare -a row_domain=()
declare -a row_action=()
declare -a row_matches=()

while IFS=$'\t' read -r path pattern domain action; do
    [[ -z "${path:-}" ]] && continue
    [[ "$path" == path ]] && continue
    if [[ -z "${pattern:-}" || -z "${domain:-}" || -z "${action:-}" ]]; then
        printf 'invalid ARC inventory row: %s\n' "$path" >&2
        exit 2
    fi
    case "$domain" in
        do_managed_value|wit_resource|test_oracle) ;;
        *) printf 'invalid ARC inventory domain: path=%s domain=%s\n' "$path" "$domain" >&2; exit 2 ;;
    esac
    case "$action" in
        replace_with_gc|retain_explicit_resource_plan|isolate_test_only) ;;
        *) printf 'invalid ARC inventory action: path=%s action=%s\n' "$path" "$action" >&2; exit 2 ;;
    esac
    row_path+=("$path")
    row_pattern+=("$pattern")
    row_domain+=("$domain")
    row_action+=("$action")
    row_matches+=(0)
done < "$inventory_path"

if (( ${#row_path[@]} == 0 )); then
    printf 'ARC inventory has no data rows: %s\n' "$inventory_path" >&2
    exit 2
fi

mapfile -t hits < <(
    cd "$ROOT"
    rg -n --no-heading --glob '*.zig' \
        '__arc_|arc-runtime|arc-layout|arc-overwrite|arc-release|arc-fallthrough-release|arc-block-release|runtime_arc_wat|emit_arc_runtime_prelude|codegen_ownership' \
        src/build || true
)

unclassified=0
normal_route_matches=0
classified_matches=0

for hit in "${hits[@]}"; do
    [[ -z "$hit" ]] && continue
    path=${hit%%:*}
    remaining=${hit#*:}
    line=${remaining%%:*}
    text=${remaining#*:}
    matched=0
    for ((index = 0; index < ${#row_path[@]}; index++)); do
        [[ "$path" != "${row_path[index]}" ]] && continue
        pattern=${row_pattern[index]}
        if [[ "$pattern" != '*' && "$text" != *"$pattern"* ]]; then
            continue
        fi
        row_matches[index]=$((row_matches[index] + 1))
        matched=1
        classified_matches=$((classified_matches + 1))
        if [[ "$mode" == post_cutover && "${row_action[index]}" == replace_with_gc ]]; then
            printf 'normal-route ARC remains: %s:%s: domain=%s action=%s\n' \
                "$path" "$line" "${row_domain[index]}" "${row_action[index]}" >&2
            normal_route_matches=$((normal_route_matches + 1))
        fi
    done
    if (( matched == 0 )); then
        printf 'unclassified ARC reference: %s:%s:%s\n' "$path" "$line" "$text" >&2
        unclassified=$((unclassified + 1))
    fi
done

for ((index = 0; index < ${#row_path[@]}; index++)); do
    if (( row_matches[index] == 0 )); then
        printf 'ARC inventory row has no matching reference: %s:%s\n' \
            "${row_path[index]}" "${row_pattern[index]}" >&2
        unclassified=$((unclassified + 1))
    fi
done

printf 'ARC inventory mode=%s rows=%d matches=%d unclassified=%d normal_route_matches=%d\n' \
    "$mode" "${#row_path[@]}" "$classified_matches" "$unclassified" "$normal_route_matches"

if (( unclassified != 0 )); then
    exit 2
fi
if (( normal_route_matches != 0 )); then
    exit 1
fi

if [[ "$mode" == post_cutover ]]; then
    # The installed compiler must not import or call the ARC prelude.  ARC
    # source remains valid only behind the explicitly test-only oracle.
    normal_roots=(
        src/main.zig
        src/build.zig
        src/build/run.zig
        src/build/codegen_api.zig
        src/build/codegen_pipeline.zig
        src/build/codegen_model.zig
    )
    mapfile -t normal_arc_refs < <(
        cd "$ROOT"
        rg -n --no-heading \
            'runtime_arc_wat|runtime_prelude_wat|emit_arc_runtime_prelude|codegen_ownership' \
            "${normal_roots[@]}" || true
    )
    if (( ${#normal_arc_refs[@]} != 0 )); then
        printf 'normal compiler ARC dependency remains:\n' >&2
        printf '%s\n' "${normal_arc_refs[@]}" >&2
        exit 1
    fi

    runtime_api=src/build/codegen_runtime_api.zig
    if [[ ! -f "$ROOT/$runtime_api" ]]; then
        printf 'missing GC-only production codegen API: %s\n' "$runtime_api" >&2
        exit 1
    fi
    mapfile -t production_legacy_imports < <(
        cd "$ROOT"
        rg -n --no-heading \
            'codegen_(api|pipeline)\.zig|runtime_(arc|prelude)_wat\.zig|codegen_ownership\.zig|wat_storage\.zig' \
            src/build/run.zig src/build/codegen_runtime_api.zig || true
    )
    if (( ${#production_legacy_imports[@]} != 0 )); then
        printf 'production codegen still imports legacy emitter modules:\n' >&2
        printf '%s\n' "${production_legacy_imports[@]}" >&2
        exit 1
    fi

    # Check the complete import closure of the installed compiler entrypoint,
    # not just its direct imports. A pure constants module must not
    # accidentally pull the legacy ARC storage/runtime emitters back into the
    # GC production graph.
    declare -A seen_modules=()
    declare -a pending_modules=(src/build/run.zig)
    while (( ${#pending_modules[@]} != 0 )); do
        module_path=${pending_modules[0]}
        pending_modules=("${pending_modules[@]:1}")
        [[ ${seen_modules[$module_path]+x} ]] && continue
        seen_modules[$module_path]=1
        while IFS= read -r import_name; do
            target_path="src/build/$import_name"
            [[ -f "$ROOT/$target_path" ]] || continue
            pending_modules+=("$target_path")
        done < <(
            cd "$ROOT"
            rg -o '@import\("[^"]+\.zig"\)' "$module_path" |
                sed -E 's/^@import\("(.*)"\)$/\1/' |
                sort -u
        )
    done

    forbidden_modules=(
        runtime_arc_wat.zig
        runtime_prelude_wat.zig
        codegen_ownership.zig
        wat_storage.zig
        codegen_emit_call.zig
        codegen_emit_expression.zig
        codegen_emit_control.zig
        codegen_emit_struct.zig
        codegen_emit_struct_fields.zig
        codegen_emit_union.zig
        codegen_emit_storage_values.zig
        codegen_emit_storage_operations.zig
        codegen_generics.zig
        codegen_api.zig
        codegen_pipeline.zig
    )
    for forbidden in "${forbidden_modules[@]}"; do
        for module_path in "${!seen_modules[@]}"; do
            if [[ "$module_path" == *"/$forbidden" ]]; then
                printf 'forbidden production dependency: %s\n' "$module_path" >&2
                exit 1
            fi
        done
    done
    printf 'GC production dependency closure: modules=%d forbidden=0\n' "${#seen_modules[@]}"
fi
