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

found_value_row=0
for domain in "${row_domain[@]}"; do
    if [[ "$domain" == do_managed_value ]]; then
        found_value_row=1
        break
    fi
done
if (( found_value_row == 0 )); then
    printf 'ARC inventory lacks a do_managed_value row\n' >&2
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
