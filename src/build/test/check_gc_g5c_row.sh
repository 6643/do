#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
INVENTORY_SCRIPT="$ROOT/src/build/test/check_gc_migration_inventory.sh"
LOCK_FILE="$ROOT/toolchain/toolchain.lock.json"
TOOLCHAIN_BIN="${DO_TOOLCHAIN_BIN:-$ROOT/bin/do-toolchain}"

usage() {
    printf 'usage: %s --row <row> --profile <S|H|A> --evidence-dir <directory>\n' "${BASH_SOURCE[0]}" >&2
}

row=''
profile=''
evidence_dir=''
while (($#)); do
    case "$1" in
        --row)
            (($# >= 2)) || { usage; exit 2; }
            row=$2
            shift 2
            ;;
        --profile)
            (($# >= 2)) || { usage; exit 2; }
            profile=$2
            shift 2
            ;;
        --evidence-dir)
            (($# >= 2)) || { usage; exit 2; }
            evidence_dir=$2
            shift 2
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

[[ -n "$row" && -n "$profile" && -n "$evidence_dir" ]] || { usage; exit 2; }
case "$profile" in
    S|H|A) ;;
    *) printf 'unknown profile: %s\n' "$profile" >&2; exit 2 ;;
esac
[[ -f "$INVENTORY_SCRIPT" ]] || { printf 'missing inventory script: %s\n' "$INVENTORY_SCRIPT" >&2; exit 2; }
[[ -f "$LOCK_FILE" ]] || { printf 'missing toolchain lock: %s\n' "$LOCK_FILE" >&2; exit 2; }
[[ -x "$TOOLCHAIN_BIN" ]] || { printf 'missing toolchain adapter: %s\n' "$TOOLCHAIN_BIN" >&2; exit 2; }
[[ -d "$evidence_dir" ]] || { printf 'evidence directory does not exist: %s\n' "$evidence_dir" >&2; exit 2; }

row_line=$(awk -F '\t' -v wanted="$row" '
    index($0, "<<\047ROWS\047") { in_rows = 1; next }
    $0 == "ROWS" { in_rows = 0; next }
    in_rows && $1 == wanted {
        if (NF != 9) exit 2
        print
        count++
    }
    END { if (count != 1) exit 1 }
' "$INVENTORY_SCRIPT") || {
    printf 'unknown or duplicate inventory row: %s\n' "$row" >&2
    exit 1
}

IFS=$'\t' read -r row_name g5a_status g5a_sources g5a_probes g5b_status g5b_evidence g5c_status g5c_evidence boundary <<< "$row_line"
fields=("$row_name" "$g5a_status" "$g5a_sources" "$g5a_probes" "$g5b_status" "$g5b_evidence" "$g5c_status" "$g5c_evidence" "$boundary")
(( ${#fields[@]} == 9 )) || { printf 'inventory row does not have nine fields: %s\n' "$row" >&2; exit 1; }
[[ "$row_name" == "$row" ]] || { printf 'inventory row mismatch: %s\n' "$row" >&2; exit 1; }
case "$row" in
    text|\[u8\]|other_lists|managed_struct_list_append|managed_structs|nested_structs|tuple_storage|unions|generic_calls|imports|sync_control_flow)
        expected_profile=S
        ;;
    host_wit_marshalling|host_wit_marshalling_managed_record_lower)
        expected_profile=H
        ;;
    future_stream_frames|resource_terminal_cleanup)
        expected_profile=A
        ;;
    *)
        printf 'row has no profile assignment: %s\n' "$row" >&2
        exit 1
        ;;
esac
[[ "$profile" == "$expected_profile" ]] || {
    printf 'profile mismatch for row %s: expected %s, got %s\n' "$row" "$expected_profile" "$profile" >&2
    exit 1
}
[[ "$g5c_status" == pending && "$g5c_evidence" == - ]] || {
    printf 'row is not pending with empty evidence: %s\n' "$row" >&2
    exit 1
}

commands_log="$evidence_dir/commands.log"
summary_file="$evidence_dir/summary.txt"
: > "$commands_log"
printf 'row=%s\nprofile=%s\n' "$row" "$profile" >> "$commands_log"
printf 'inventory=%s\n' "$row_line" >> "$commands_log"
printf 'commit=%s\nbranch=%s\n' "$(git -C "$ROOT" rev-parse HEAD)" "$(git -C "$ROOT" branch --show-current)" >> "$commands_log"
printf 'toolchain_lock=%s\n' "$LOCK_FILE" >> "$commands_log"

probe_file="$evidence_dir/toolchain-probe.json"
printf '%s\n' '+ bin/do-toolchain probe' >> "$commands_log"
if ! "$TOOLCHAIN_BIN" probe >"$probe_file" 2>"$evidence_dir/toolchain-probe.stderr"; then
    printf 'toolchain probe failed; see %s\n' "$evidence_dir/toolchain-probe.stderr" >&2
    exit 1
fi
cat "$probe_file" >> "$commands_log"
if ! jq -n -e --slurpfile lock "$LOCK_FILE" --slurpfile probe "$probe_file" '
    $probe[0].schema == $lock[0].schema and
    $probe[0].wasm_tools == ($lock[0].wasm_tools | {path, version, sha256}) and
    $probe[0].wasmtime == ($lock[0].wasmtime | {path, version, sha256}) and
    $lock[0].rust_wasmtime.status == "verified" and
    $lock[0].rust_wasmtime.version == $lock[0].rust_wasmtime.target_version
' >/dev/null; then
    printf 'toolchain probe does not match pinned lock\n' >&2
    exit 1
fi

run_gate() {
    local name=$1
    shift
    local output="$evidence_dir/$name.log"
    printf '\n$' >> "$commands_log"
    printf ' %q' "$@" >> "$commands_log"
    printf '\n' >> "$commands_log"
    set +e
    (cd "$ROOT" && ZIG_GLOBAL_CACHE_DIR="$evidence_dir/zig-cache" "$@") >"$output" 2>&1
    local rc=$?
    set -e
    printf '%s exit=%d output=%s\n' "$name" "$rc" "$output" >> "$commands_log"
    if ((rc != 0)); then
        printf '%s failed (exit %d); see %s\n' "$name" "$rc" "$output" >&2
        return 1
    fi
}

verify_paths() {
    local label=$1
    local list=$2
    [[ "$list" != '-' && -n "$list" ]] || { printf '%s list is empty\n' "$label" >&2; return 1; }
    local path
    local -a paths
    IFS=',' read -r -a paths <<< "$list"
    for path in "${paths[@]}"; do
        [[ -n "$path" && "$path" != *$'\n'* ]] || { printf 'invalid %s path\n' "$label" >&2; return 1; }
        [[ -e "$ROOT/$path" ]] || { printf 'missing %s path: %s\n' "$label" "$path" >&2; return 1; }
    done
}

verify_paths g5a_fixture "$g5a_sources"
verify_paths g5a_probe "$g5a_probes"
verify_paths g5b_evidence "$g5b_evidence"

run_gate arc_inventory bash "$ROOT/src/build/test/check_gc_arc_inventory.sh" --post-cutover
run_gate default_build bash "$ROOT/src/build/test/check_gc_default_build_gate.sh"
run_gate migration_evidence bash "$ROOT/src/build/test/check_gc_migration_evidence_test.sh"

case "$profile" in
    S) route_label='synchronous GC' ;;
    H) route_label='synchronous host/WIT' ;;
    A) route_label='Future/resource' ;;
esac

run_path_list() {
    local label=$1
    local list=$2
    local path
    local -a paths
    IFS=',' read -r -a paths <<< "$list"
    for path in "${paths[@]}"; do
        run_gate "$label-$(basename "$path" .sh)" bash "$ROOT/$path"
    done
}

run_path_list g5a "$g5a_probes"
run_path_list g5b "$g5b_evidence"

cat > "$summary_file" <<EOF
row=$row
profile=$profile
route=$route_label
g5a_status=$g5a_status
g5b_status=$g5b_status
g5c_status=$g5c_status
boundary=$boundary
commands_log=$commands_log
toolchain_probe=$probe_file
result=passed
EOF
printf 'row=%s profile=%s result=passed summary=%s\n' "$row" "$profile" "$summary_file"
