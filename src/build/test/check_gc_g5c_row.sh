#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
INVENTORY_SCRIPT="$ROOT/src/build/test/check_gc_migration_inventory.sh"
LOCK_FILE="$ROOT/toolchain/toolchain.lock.json"
TOOLCHAIN_BIN="$ROOT/bin/do-toolchain"
WASM_TOOLS_BIN="$(jq -r '.wasm_tools.path' "$ROOT/toolchain/toolchain.lock.json" 2>/dev/null || true)"

if [[ -n "${DO_TOOLCHAIN_BIN+x}" || -n "${DO_TOOLCHAIN_LOCK+x}" ]]; then
    printf 'toolchain adapter/lock overrides are not permitted\n' >&2
    exit 2
fi

usage() {
    printf 'usage: %s --row <row> --profile <S|H|A> --evidence-dir <directory>\n' "${BASH_SOURCE[0]}" >&2
}

row=''
profile=''
evidence_dir=''
self_test=0
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
        --self-test)
            self_test=1
            shift
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
evidence_dir=$(realpath -e -- "$evidence_dir") || {
    printf 'cannot resolve evidence directory: %s\n' "$evidence_dir" >&2
    exit 2
}

DO_BIN_PIN="$ROOT/bin/do"
PINNED_RUST_CC="$ROOT/examples/p3-runtime/rust-host-runner/zig-cc.sh"
WASMTIME_BIN="$(jq -r '.wasmtime.path' "$LOCK_FILE" 2>/dev/null || true)"

resolve_tool() {
    local requested=$1
    local resolved=''
    case "$requested" in
        /*)
            resolved=$(realpath -e -- "$requested" 2>/dev/null || true)
            ;;
        */*)
            resolved=$(realpath -e -- "$ROOT/$requested" 2>/dev/null || true)
            ;;
        *)
            resolved=$(type -P -- "$requested" 2>/dev/null || true)
            ;;
    esac
    [[ -n "$resolved" && -x "$resolved" ]] || {
        printf 'tool is not executable: requested=%s resolved=%s\n' "$requested" "$resolved" >&2
        return 1
    }
    printf '%s\n' "$resolved"
}

validate_tool() {
    local label=$1
    local requested=$2
    local expected_version=$3
    local expected_sha=$4
    local version_mode=$5
    local output_name=$6
    local resolved actual_version actual_sha=''

    resolved=$(resolve_tool "$requested") || return 1
    if [[ "$version_mode" == zig ]]; then
        actual_version=$("$resolved" version 2>&1) || {
            printf '%s version probe failed: %s\n' "$label" "$resolved" >&2
            return 1
        }
    else
        actual_version=$("$resolved" --version 2>&1) || {
            printf '%s version probe failed: %s\n' "$label" "$resolved" >&2
            return 1
        }
    fi
    if [[ -n "$expected_version" && "$actual_version" != "$expected_version" ]]; then
        printf '%s version mismatch: expected=%s actual=%s\n' \
            "$label" "$expected_version" "$actual_version" >&2
        return 1
    fi
    if [[ -n "$expected_sha" ]]; then
        [[ "$expected_sha" =~ ^[0-9a-fA-F]{64}$ ]] || {
            printf '%s hash is not a 64-character SHA-256 digest: %s\n' \
                "$label" "$expected_sha" >&2
            return 1
        }
        actual_sha=$(sha256sum -- "$resolved" | awk '{print $1}') || return 1
        [[ "$actual_sha" == "$expected_sha" ]] || {
            printf '%s hash mismatch: expected=%s actual=%s\n' \
                "$label" "$expected_sha" "$actual_sha" >&2
            return 1
        }
    fi
    printf -v "$output_name" '%s' "$resolved"
}

load_toolchain() {
    local zig_path zig_version zig_sha rustc_path rustc_version rustc_sha
    local cargo_path cargo_version cargo_sha
    zig_path=$(jq -er '.zig.path' "$LOCK_FILE") || return 1
    zig_version=$(jq -er '.zig.version' "$LOCK_FILE") || return 1
    zig_sha=$(jq -er '.zig.sha256' "$LOCK_FILE") || return 1
    rustc_path=$(jq -er '.rustc.path' "$LOCK_FILE") || return 1
    rustc_version=$(jq -er '.rustc.version' "$LOCK_FILE") || return 1
    rustc_sha=$(jq -er '.rustc.sha256' "$LOCK_FILE") || return 1
    cargo_path=$(jq -er '.cargo.path' "$LOCK_FILE") || return 1
    cargo_version=$(jq -er '.cargo.version' "$LOCK_FILE") || return 1
    cargo_sha=$(jq -er '.cargo.sha256' "$LOCK_FILE") || return 1

    validate_tool zig "$zig_path" "$zig_version" "$zig_sha" zig ZIG_BIN_PIN || return 1
    validate_tool rustc "$rustc_path" "$rustc_version" "$rustc_sha" rust RUSTC_BIN_PIN || return 1
    validate_tool cargo "$cargo_path" "$cargo_version" "$cargo_sha" rust CARGO_BIN_PIN || return 1
    [[ -x "$DO_BIN_PIN" ]] || {
        printf 'missing do compiler: %s\n' "$DO_BIN_PIN" >&2
        return 1
    }
    [[ -x "$PINNED_RUST_CC" ]] || {
        printf 'missing Rust linker wrapper: %s\n' "$PINNED_RUST_CC" >&2
        return 1
    }
}

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
[[ "$g5a_status" == complete && "$g5b_status" == complete ]] || {
    printf 'row has incomplete prerequisite status: g5a=%s g5b=%s\n' "$g5a_status" "$g5b_status" >&2
    exit 1
}

commands_log="$evidence_dir/commands.log"
summary_file="$evidence_dir/summary.txt"
mkdir -p "$evidence_dir/tmp"
: > "$commands_log"
printf 'row=%s\nprofile=%s\n' "$row" "$profile" >> "$commands_log"
printf 'inventory=%s\n' "$row_line" >> "$commands_log"
printf 'commit=%s\nbranch=%s\n' "$(git -C "$ROOT" rev-parse HEAD)" "$(git -C "$ROOT" branch --show-current)" >> "$commands_log"
printf 'toolchain_lock=%s\n' "$LOCK_FILE" >> "$commands_log"
printf 'toolchain_lock_json<<BEGIN\n' >> "$commands_log"
cat "$LOCK_FILE" >> "$commands_log"
printf 'toolchain_lock_json<<END\n' >> "$commands_log"
if ! load_toolchain; then
    printf 'toolchain validation failed\n' >&2
    exit 1
fi
for tool_name in zig rustc cargo; do
    printf 'tool=%s requested=%s resolved=%s version=%s sha256=%s\n' \
        "$tool_name" \
        "$(jq -r ".${tool_name}.path" "$LOCK_FILE")" \
        "$(case "$tool_name" in zig) printf '%s' "$ZIG_BIN_PIN" ;; rustc) printf '%s' "$RUSTC_BIN_PIN" ;; cargo) printf '%s' "$CARGO_BIN_PIN" ;; esac)" \
        "$(jq -r ".${tool_name}.version" "$LOCK_FILE")" \
        "$(jq -r ".${tool_name}.sha256" "$LOCK_FILE")" >> "$commands_log"
done
export DO_TOOLCHAIN_LOCK="$LOCK_FILE"

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
    $lock[0].rust_wasmtime.status == "current" and
    $lock[0].rust_wasmtime.version == $lock[0].rust_wasmtime.target_version
' >/dev/null; then
    printf 'toolchain probe does not match lock configuration\n' >&2
    exit 1
fi

run_gate_expected() {
    local name=$1
    local expected=$2
    shift 2
    local output="$evidence_dir/$name.log"
    printf '\n$' >> "$commands_log"
    printf ' %q' "$@" >> "$commands_log"
    printf '\n' >> "$commands_log"
    set +e
    (
        cd "$ROOT"
        DO_BIN="$DO_BIN_PIN" \
        DO_TOOLCHAIN_BIN="$TOOLCHAIN_BIN" \
        DO_TOOLCHAIN_LOCK="$LOCK_FILE" \
        WASM_TOOLS_BIN="$WASM_TOOLS_BIN" \
        WASMTIME_BIN="$WASMTIME_BIN" \
        ZIG_BIN="$ZIG_BIN_PIN" \
        RUSTC="$RUSTC_BIN_PIN" \
        CARGO_BIN="$CARGO_BIN_PIN" \
        CC="$PINNED_RUST_CC" \
        CXX="$PINNED_RUST_CC" \
        CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PINNED_RUST_CC" \
        CARGO_TARGET_DIR="$evidence_dir/cargo-target" \
        TMPDIR="$evidence_dir/tmp" \
        ZIG_LOCAL_CACHE_DIR="$evidence_dir/zig-cache/local" \
        ZIG_GLOBAL_CACHE_DIR="$evidence_dir/zig-cache/global" \
        "$@"
    ) >"$output" 2>&1
    local rc=$?
    set -e
    printf '%s expected_exit=%d actual_exit=%d output=%s\n' "$name" "$expected" "$rc" "$output" >> "$commands_log"
    if ((rc != expected)); then
        printf '%s failed (expected exit %d, actual %d); see %s\n' "$name" "$expected" "$rc" "$output" >&2
        return 1
    fi
    if ((rc == 0)); then
        record_gate_artifact_paths "$output" || return 1
    fi
}

run_gate() {
    local name=$1
    shift
    run_gate_expected "$name" 0 "$@"
}

check_inventory_status_log() {
    local output=$1
    local expected_pending=$2
    local expected_summary="summary complete_rows=15 pending_rows=$expected_pending"
    local summary_count
    summary_count=$(rg -c '^summary complete_rows=[0-9]+ pending_rows=[0-9]+$' "$output" || true)
    [[ "$summary_count" == 1 ]] || {
        printf 'inventory status must contain exactly one summary line: %s\n' "$output" >&2
        return 1
    }
    rg -Fxq -- "$expected_summary" "$output" || {
        printf 'inventory status summary mismatch: expected=%s output=%s\n' "$expected_summary" "$output" >&2
        return 1
    }
}

normalize_artifact_path() {
    local path=$1
    case "$path" in
        /.tmp/*)
            printf '%s%s\n' "$ROOT" "$path"
            ;;
        *)
            printf '%s\n' "$path"
            ;;
    esac
}

resolve_artifact_path() {
    local raw_path=$1
    local path
    local capture_root="${G5C_ARTIFACT_CAPTURE_ROOT%/}"
    local tmp_root="${G5C_ARTIFACT_TMP_ROOT%/}"
    local candidate rel resolved

    path=$(normalize_artifact_path "$raw_path") || return 1
    [[ "$path" == /* && "$path" != *$'\n'* ]] || return 1
    if [[ -e "$path" || -L "$path" ]]; then
        candidate=$path
    elif [[ "$path" == "$tmp_root"/* ]]; then
        rel="${path#"$tmp_root"/}"
        [[ -n "$rel" && "$rel" != "$path" ]] || return 1
        candidate="$capture_root/$rel"
    else
        return 1
    fi
    [[ -e "$candidate" || -L "$candidate" ]] || return 1
    resolved=$(realpath -e -- "$candidate") || return 1
    [[ "$resolved" == "$evidence_dir"/* ]] || return 1
    printf '%s\n' "$resolved"
}

record_gate_artifact_paths() {
    local output=$1
    local raw path normalized_path resolved
    while IFS= read -r raw; do
        path=${raw#"${raw%%[![:space:]]*}"}
        [[ -n "$path" ]] || continue
        normalized_path=$(normalize_artifact_path "$path") || {
            printf 'cannot normalize emitted artifact path: %s\n' "$path" >&2
            return 1
        }
        # Negative probes commonly mention a would-be output path in their
        # diagnostic, even though no artifact was created. It is not an
        # evidence artifact when it is inside this run's temporary root and
        # neither the live path nor its captured replacement exists. An
        # existing path outside the evidence root remains a hard failure.
        if [[ "$normalized_path" == "${G5C_ARTIFACT_TMP_ROOT%/}"/* ]] && \
            [[ ! -e "$normalized_path" && ! -L "$normalized_path" ]]; then
            rel=${normalized_path#"${G5C_ARTIFACT_TMP_ROOT%/}"/}
            if [[ ! -e "${G5C_ARTIFACT_CAPTURE_ROOT%/}/$rel" && \
                ! -L "${G5C_ARTIFACT_CAPTURE_ROOT%/}/$rel" ]]; then
                continue
            fi
        fi
        if is_negative_artifact "$normalized_path"; then
            continue
        fi
        if [[ "$normalized_path" == "$ROOT/"* ]] && \
            [[ -e "$normalized_path" || -L "$normalized_path" ]]; then
            rel=${normalized_path#"$ROOT/"}
            if git -C "$ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
                printf '%s\n' "$(realpath -e -- "$normalized_path")" >> "$G5C_ARTIFACT_REFERENCE_PATHS"
                continue
            fi
        fi
        resolved=$(resolve_artifact_path "$path") || {
            printf 'gate emitted artifact path outside current evidence root: %s\n' "$path" >&2
            return 1
        }
        printf '%s\n' "$resolved" >> "$evidence_dir/artifact-paths.log"
    done < <(rg -o "(^|[[:space:]])/[^[:space:]\"]+\.(wat|core\.wat|wasm|component\.wasm|wit)" "$output" | sed 's/^[[:space:]]*//')
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
        case "$path" in
            /*|..|../*|*/../*)
                printf 'unsafe %s path: %s\n' "$label" "$path" >&2
                return 1
                ;;
        esac
        [[ -e "$ROOT/$path" ]] || { printf 'missing %s path: %s\n' "$label" "$path" >&2; return 1; }
        resolved=$(realpath -e -- "$ROOT/$path") || { printf 'cannot resolve %s path: %s\n' "$label" "$path" >&2; return 1; }
        [[ "$resolved" == "$ROOT"/* ]] || {
            printf '%s path escapes repository: %s -> %s\n' "$label" "$path" "$resolved" >&2
            return 1
        }
    done
}

has_forbidden_canonical_import_ref() {
    local file=$1
    perl -0777 -e '
        my $wat = <>;
        sub close_at {
            my ($s, $start) = @_;
            my ($depth, $quote, $escape) = (0, 0, 0);
            for (my $i = $start; $i < length($s); ++$i) {
                my $c = substr($s, $i, 1);
                if ($quote) {
                    if ($escape) { $escape = 0; next; }
                    if ($c eq "\\") { $escape = 1; next; }
                    $quote = 0 if $c eq "\"";
                    next;
                }
                if ($c eq "\"") { $quote = 1; next; }
                $depth++ if $c eq "(";
                if ($c eq ")") {
                    --$depth;
                    return $i if $depth == 0;
                }
            }
            return undef;
        }
        sub forms {
            my ($s, $name) = @_;
            my @result;
            while ($s =~ /\(\Q$name\E\b/g) {
                my $start = $-[0];
                my $end = close_at($s, $start);
                return () unless defined $end;
                push @result, substr($s, $start, $end - $start + 1);
                pos($s) = $end + 1;
            }
            return @result;
        }
        my %gc_func_types;
        my %gc_func_type_names;
        for my $type (forms($wat, "type")) {
            my ($type_name, $type_index);
            if ($type !~ /^\(type(?:\s+\$([^\s()]+))?(?:\s+\(;\s*(\d+)\s*;\))?\s+\(func\b/s) {
                next;
            }
            ($type_name, $type_index) = ($1, $2);
            my @funcs = forms($type, "func");
            next unless @funcs == 1;
            if ($funcs[0] =~ /\(ref\b/) {
                $gc_func_types{$type_index} = 1 if defined $type_index;
                $gc_func_type_names{$type_name} = 1 if defined $type_name;
            }
        }
        for my $import (forms($wat, "import")) {
            my @funcs = forms($import, "func");
            next unless @funcs == 1;
            my $func = $funcs[0];
            exit 0 if $func =~ /\(ref\b/;
            if ($func =~ /\(type\s+(\d+)\b/) {
                my $type_index = $1;
                exit 0 if $gc_func_types{$type_index};
            } elsif ($func =~ /\(type\s+\$([^\s()]+)\b/) {
                my $type_name = $1;
                exit 0 if $gc_func_type_names{$type_name};
            }
        }
        exit 1;
    ' "$file"
}

check_common_artifacts() {
    local file
    : > "$evidence_dir/artifact-check.log"
    declare -A seen=()
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        resolved=$(resolve_artifact_path "$file") || {
            printf 'cannot resolve referenced artifact: %s\n' "$file" >&2
            return 1
        }
        file=$resolved
        is_negative_artifact "$file" && continue
        [[ ${seen[$file]+x} ]] && continue
        seen[$file]=1
        [[ -f "$file" ]] || {
            printf 'referenced artifact is missing: %s\n' "$file" >&2
            return 1
        }
        printf '%s\n' "$file" >> "$evidence_dir/artifact-check.log"
        check_artifact_content "$file" || return 1
    done < <(
        fd --type f --glob '*.wat' --glob '*.core.wat' --glob '*.wasm' --glob '*.component.wasm' --glob '*.wit' --exclude '*.printed.wat' . "$evidence_dir"
        [[ -f "$evidence_dir/artifact-paths.log" ]] && sed '/^$/d' "$evidence_dir/artifact-paths.log"
    )
}

is_negative_artifact() {
    local file=$1
    case "$file" in
        */negative-*|*/negative.*|*/gc-import.wat)
            return 0
            ;;
    esac
    [[ -n "${G5C_ARTIFACT_NEGATIVE_PATHS:-}" && -f "$G5C_ARTIFACT_NEGATIVE_PATHS" ]] && \
        rg -Fxq -- "$file" "$G5C_ARTIFACT_NEGATIVE_PATHS"
}

check_artifact_content() {
    local file=$1
    if rg -n -q '__arc_|arc-runtime|arc-layout|arc-overwrite|arc-release|arc-fallthrough-release|arc-block-release' "$file"; then
        printf 'ARC marker in admitted artifact: %s\n' "$file" >&2
        return 1
    fi
    case "$file" in
        *.wasm|*.component.wasm)
            local printed="$evidence_dir/$(basename "$file").printed.wat"
            [[ -x "$WASM_TOOLS_BIN" ]] || { printf 'missing wasm-tools: %s\n' "$WASM_TOOLS_BIN" >&2; return 1; }
            if ! "$TOOLCHAIN_BIN" print-component "$file" >"$printed" 2>/dev/null; then
                printf 'wasm-tools print failed for binary artifact: %s\n' "$file" >&2
                return 1
            fi
            [[ -s "$printed" ]] || {
                printf 'wasm-tools print produced no output for binary artifact: %s\n' "$file" >&2
                return 1
            }
            if has_forbidden_canonical_import_ref "$printed"; then
                printf 'GC reference in binary canonical import artifact: %s\n' "$file" >&2
                return 1
            fi
            ;;
        *.wat|*.core.wat)
            if has_forbidden_canonical_import_ref "$file"; then
                printf 'GC reference in canonical import artifact: %s\n' "$file" >&2
                return 1
            fi
            ;;
    esac
}

check_negative_artifacts() {
    local file
    : > "$evidence_dir/negative-artifact-check.log"
    [[ -f "${G5C_ARTIFACT_NEGATIVE_PATHS:-}" ]] || return 0
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        resolved=$(realpath -e -- "$file") || {
            printf 'cannot resolve referenced negative artifact: %s\n' "$file" >&2
            return 1
        }
        [[ "$resolved" == "$evidence_dir"/* ]] || {
            printf 'referenced negative artifact escapes evidence root: %s -> %s\n' "$file" "$resolved" >&2
            return 1
        }
        [[ -f "$resolved" ]] || {
            printf 'referenced negative artifact is missing: %s\n' "$file" >&2
            return 1
        }
        printf '%s\n' "$resolved" >> "$evidence_dir/negative-artifact-check.log"
    done < "$G5C_ARTIFACT_NEGATIVE_PATHS"
}

check_reference_artifacts() {
    local file resolved rel
    local check_log="$evidence_dir/reference-artifact-check.log"
    : > "$check_log"
    [[ -f "${G5C_ARTIFACT_REFERENCE_PATHS:-}" ]] || return 0
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        resolved=$(realpath -e -- "$file") || {
            printf 'cannot resolve referenced repository artifact: %s\n' "$file" >&2
            return 1
        }
        [[ "$resolved" == "$ROOT/"* ]] || {
            printf 'referenced repository artifact escapes repository: %s -> %s\n' "$file" "$resolved" >&2
            return 1
        }
        rel=${resolved#"$ROOT/"}
        git -C "$ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || {
            printf 'referenced repository artifact is not tracked: %s\n' "$file" >&2
            return 1
        }
        is_negative_artifact "$resolved" && continue
        printf '%s\n' "$resolved" >> "$check_log"
        check_artifact_content "$resolved" || return 1
    done < "$G5C_ARTIFACT_REFERENCE_PATHS"
}

check_h_component_log_chain() {
    local log=$1
    perl -0777 -e '
        my $text = <>;
        my @lines = split /\n/, $text;
        my (@parse, @embed, @new, @validate);
        for my $line_no (0 .. $#lines) {
            my $line = $lines[$line_no];
            if ($line =~ /\bparse-core\s+(\S+\.wat)\s+-o\s+(\S+\.wasm)\b/) {
                push @parse, [$line_no, $1, $2];
            }
            if ($line =~ /\bembed-component\s+(\S+)\s+(\S+\.wasm)\b.*?\s-o\s+(\S+\.wasm)\b/) {
                my ($wit_source, $core_wasm, $embedded_wasm) = ($1, $2, $3);
                next unless $wit_source =~ /\.wit\z/ || -d $wit_source;
                push @embed, [$line_no, $wit_source, $core_wasm, $embedded_wasm];
            }
            if ($line =~ /\bnew-component\s+(\S+\.wasm)\s+-o\s+(\S+component\.wasm)\b/) {
                push @new, [$line_no, $1, $2];
            }
            if ($line =~ /\bvalidate-component\s+(\S+component\.wasm)\b/) {
                push @validate, [$line_no, $1];
            }
        }
        for my $parse (@parse) {
            for my $embed (@embed) {
                next if $embed->[0] <= $parse->[0];
                next unless $embed->[2] eq $parse->[2];
                for my $new (@new) {
                    next if $new->[0] <= $embed->[0];
                    next unless $new->[1] eq $embed->[3];
                    for my $validate (@validate) {
                        next if $validate->[0] <= $new->[0];
                        next unless $validate->[1] eq $new->[2];
                        exit 0;
                    }
                }
            }
        }
        exit 1;
    ' "$log"
}

check_h_component_steps() {
    local log positive=0
    local -a logs=("$evidence_dir"/g5a-*.log "$evidence_dir"/g5b-*.log)
    for log in "${logs[@]}"; do
        [[ -f "$log" ]] || continue
        if ! rg -q -- '(^|[[:space:]])parse-core([[:space:]]|$)' "$log"; then
            continue
        fi
        positive=1
        check_h_component_log_chain "$log" || {
            printf 'H Component evidence is not a single parse/embed/new/validate artifact chain: %s\n' "$log" >&2
            return 1
        }
    done
    ((positive)) || {
        printf 'H profile has no artifact-producing gate with Component evidence\n' >&2
        return 1
    }
}

check_profile_artifacts() {
    check_negative_artifacts || return 1
    check_reference_artifacts || return 1
    case "$profile" in
        S)
            check_common_artifacts || return 1
            ;;
        H)
            check_common_artifacts || return 1
            check_h_component_steps || return 1
            [[ -s "$evidence_dir/artifact-check.log" ]] || {
                printf 'H profile has no generated artifact to inspect\n' >&2
                return 1
            }
            ;;
        A)
            check_common_artifacts || return 1
            case "$row" in
                future_stream_frames)
                    local future_frames_log="$evidence_dir/g5a-test_gc_async_frame_component.log"
                    local future_equivalence_log="$evidence_dir/g5b-test_gc_async_frame_equivalence.log"
                    local -a future_logs=("$future_frames_log" "$future_equivalence_log")
                    [[ -f "$future_frames_log" && -f "$future_equivalence_log" ]] || {
                        printf 'future lifecycle evidence is not bound to the selected row\n' >&2
                        return 1
                    }
                    rg -q '^Do bounded async GC frame/table component passed: fixture=two-await-component\.do$' "$future_frames_log" || {
                        printf 'future frame/table probe output is missing\n' >&2
                        return 1
                    }
                    rg -q '^GC/linear Future frame equivalence passed rows=1 ready=unsupported-sync-completion pending-polls=4 external-wakes=4 completions=4$' "$future_equivalence_log" || {
                        printf 'future lifecycle counters are not exact\n' >&2
                        return 1
                    }
                    for expected in \
                        'future lifecycle case=pending pending-polls=4 external-wakes=4 completions=4' \
                        'future lifecycle case=error host-errors=1 completions=0' \
                        'future lifecycle case=cancel host-calls=1 cancelled=1' \
                        'future lifecycle case=early-drop host-calls=0 cancelled=1' \
                        'future lifecycle case=repeat runs=2 pending-polls=8 external-wakes=8 completions=8'; do
                        rg -q -- "^$expected$" "${future_logs[@]}" || {
                            printf 'future lifecycle evidence missing exact case: %s\n' "$expected" >&2
                            return 1
                        }
                    done
                    for expected in \
                        'future lifecycle case=ready status=unsupported-sync-completion backend=gc' \
                        'future lifecycle case=ready status=unsupported-sync-completion backend=linear'; do
                        rg -q -- "^$expected$" "$future_equivalence_log" || {
                            printf 'future ready completion boundary evidence is missing: %s\n' "$expected" >&2
                            return 1
                        }
                    done
                    ;;
                resource_terminal_cleanup)
                    local resource_terminal_log="$evidence_dir/g5a-test_gc_resource_terminal_cleanup.log"
                    local resource_cancel_log="$evidence_dir/g5b-test_rust_resource_cancellation_shape.log"
                    local -a resource_logs=("$resource_terminal_log" "$resource_cancel_log")
                    [[ -f "$resource_terminal_log" && -f "$resource_cancel_log" ]] || {
                        printf 'resource lifecycle evidence is not bound to the selected row\n' >&2
                        return 1
                    }
                    rg -q '^Do bounded GC resource terminal cleanup passed: fixture=async-resource-result-component\.do$' "$resource_terminal_log" || {
                        printf 'resource lifecycle evidence missing GC frame/table markers\n' >&2
                        return 1
                    }
                    for lifecycle in ready pending error repeat; do
                        case "$lifecycle" in
                            ready|pending) expected_tail='request consumed=2 response create=2 response drop=2 table-empty=true' ;;
                            error) expected_tail='request consumed=2 response create=0 response drop=0 table-empty=true' ;;
                            repeat) expected_tail='request consumed=4 response create=4 response drop=4 table-empty=true' ;;
                        esac
                        for backend in gc linear; do
                            expected="resource lifecycle case=$lifecycle backend=$backend $expected_tail"
                            rg -q -- "^$expected$" "${resource_logs[@]}" || {
                                printf 'resource lifecycle evidence missing exact case: %s\n' "$expected" >&2
                                return 1
                            }
                        done
                    done
                    for lifecycle in cancel early-drop; do
                        if [[ "$lifecycle" == cancel ]]; then
                            expected_tail='request consumed=1 pending polls=1 pending future drops=1 response create=0 response drop=0 table-empty=true'
                        else
                            expected_tail='request consumed=0 pending polls=0 pending future drops=0 response create=0 response drop=0 table-empty=true'
                        fi
                        for backend in gc linear; do
                            expected="resource lifecycle case=$lifecycle backend=$backend $expected_tail"
                            rg -q -- "^$expected$" "$resource_cancel_log" || {
                                printf 'resource lifecycle evidence missing exact case: %s\n' "$expected" >&2
                                return 1
                            }
                        done
                    done
                    rg -q '^resource Result cancellation GC/linear equivalence passed$' "$resource_cancel_log" || {
                        printf 'resource lifecycle equivalence evidence is missing\n' >&2
                        return 1
                    }
                    ;;
                *)
                    printf 'A profile has no lifecycle schema: %s\n' "$row" >&2
                    return 1
                    ;;
            esac || {
                printf 'A profile lifecycle observations incomplete for row: %s\n' "$row" >&2
                return 1
            }
            ;;
    esac
}

g5c_artifact_capture_rm() {
    local tmp_root="${G5C_ARTIFACT_TMP_ROOT%/}"
    local capture_root="${G5C_ARTIFACT_CAPTURE_ROOT%/}"
    local paths_file="$G5C_ARTIFACT_PATHS"
    local negative_paths_file="${G5C_ARTIFACT_NEGATIVE_PATHS:-}"
    local -a targets=()
    local after_separator=0
    local arg target rel destination file

    for arg in "$@"; do
        if ((after_separator)); then
            targets+=("$arg")
            continue
        fi
        case "$arg" in
            --)
                after_separator=1
                ;;
            -*)
                ;;
            *)
                targets+=("$arg")
                ;;
        esac
    done

    for target in "${targets[@]}"; do
        [[ "$target" == "$tmp_root"/* ]] || continue
        [[ -e "$target" || -L "$target" ]] || continue
        rel="${target#"$tmp_root"/}"
        [[ -n "$rel" && "$rel" != "$target" ]] || continue
        case "$rel" in
            ..|../*)
                continue
                ;;
        esac
        destination="$capture_root/$rel"
        if [[ -e "$destination" || -L "$destination" ]]; then
            destination="$destination.capture.${BASHPID}.${RANDOM}"
        fi
        mkdir -p -- "$(dirname -- "$destination")"
        if ! cp -a -- "$target" "$destination"; then
            printf 'artifact capture failed before rm: %s\n' "$target" >&2
            return 1
        fi
        while IFS= read -r -d '' file; do
            case "$file" in
                */negative-*|*/negative.*|*/gc-import.wat)
                    printf '%s\n' "$file" >> "$negative_paths_file"
                    ;;
                *)
                    [[ "$file" != *$'\n'* ]] || {
                        printf 'artifact path contains newline: %s\n' "$file" >&2
                        return 1
                    }
                    printf '%s\n' "$file" >> "$paths_file"
                    ;;
            esac
        done < <(fd --type f --glob '*.wat' --glob '*.core.wat' --glob '*.wasm' --glob '*.component.wasm' --glob '*.wit' --print0 . "$destination")
    done

    command rm "$@"
}

install_artifact_capture() {
    local capture_env="$evidence_dir/tmp/artifact-capture.bashenv"
    local capture_root="$evidence_dir/artifacts"
    local paths_file="$evidence_dir/artifact-paths.log"
    local negative_paths_file="$evidence_dir/negative-artifact-paths.log"
    local reference_paths_file="$evidence_dir/reference-artifact-paths.log"
    if [[ -d "$capture_root" ]] && [[ -n "$(fd --type f --type d --max-depth 1 --max-results 1 . "$capture_root")" ]]; then
        printf 'evidence artifact capture root is not empty: %s\n' "$capture_root" >&2
        return 1
    fi
    if [[ -s "$paths_file" ]]; then
        printf 'evidence artifact manifest is not empty: %s\n' "$paths_file" >&2
        return 1
    fi
    if fd --type f --glob '*.wat' --glob '*.core.wat' --glob '*.wasm' --glob '*.component.wasm' --glob '*.wit' --max-results 1 . "$evidence_dir" | rg -q .; then
        printf 'evidence directory already contains boundary artifacts: %s\n' "$evidence_dir" >&2
        return 1
    fi
    mkdir -p "$capture_root"
    : > "$paths_file"
    : > "$negative_paths_file"
    : > "$reference_paths_file"
    {
        declare -f g5c_artifact_capture_rm
        printf '%s\n' 'rm() { g5c_artifact_capture_rm "$@"; }'
    } > "$capture_env"
    chmod 700 "$capture_env"
    export BASH_ENV="$capture_env"
    export G5C_ARTIFACT_CAPTURE_ROOT="$capture_root"
    export G5C_ARTIFACT_PATHS="$paths_file"
    export G5C_ARTIFACT_NEGATIVE_PATHS="$negative_paths_file"
    export G5C_ARTIFACT_REFERENCE_PATHS="$reference_paths_file"
    export G5C_ARTIFACT_TMP_ROOT="$evidence_dir/tmp"
}

run_self_tests() {
    local test_dir="$evidence_dir/self-test"
    local capture_source="$evidence_dir/tmp/self-capture-source"
    local capture_root="$evidence_dir/artifacts"
    local escape_source="$evidence_dir/tmp/../capture-escape.wat"
    local artifact="$test_dir/clean.wat"
    local alias_root alias_root_rel alias_artifact alias_path alias_outside_root alias_outside_path
    local original_evidence_dir="$evidence_dir"
    local original_bash_env="$BASH_ENV"
    local original_capture_root="$G5C_ARTIFACT_CAPTURE_ROOT"
    local original_paths_file="$G5C_ARTIFACT_PATHS"
    local original_negative_paths_file="$G5C_ARTIFACT_NEGATIVE_PATHS"
    local original_tmp_root="$G5C_ARTIFACT_TMP_ROOT"
    local stale_evidence="$evidence_dir/stale-run"
    local self_test_tool_pin=''
    local tracked_arc_artifact="$ROOT/src/build/runtime_arc_wat.zig"
    mkdir -p "$test_dir"
    if validate_tool self-test "$ZIG_BIN_PIN" "$("$ZIG_BIN_PIN" version)" "" zig self_test_tool_pin; then
        printf 'self-test failed: empty tool hash was accepted\n' >&2
        return 1
    fi
    printf 'summary complete_rows=15 pending_rows=15\n' > "$test_dir/inventory-status.log"
    if ! check_inventory_status_log "$test_dir/inventory-status.log" 15; then
        printf 'self-test failed: valid inventory baseline was rejected\n' >&2
        return 1
    fi
    printf 'summary complete_rows=15 pending_rows=14\n' > "$test_dir/inventory-status.log"
    if check_inventory_status_log "$test_dir/inventory-status.log" 15; then
        printf 'self-test failed: mismatched inventory baseline was accepted\n' >&2
        return 1
    fi
    mkdir -p "$stale_evidence/artifacts" "$stale_evidence/tmp"
    printf '(module (func $stale))\n' > "$stale_evidence/artifacts/old.wat"
    evidence_dir="$stale_evidence"
    if install_artifact_capture; then
        printf 'self-test failed: stale evidence root was accepted\n' >&2
        return 1
    fi
    evidence_dir="$original_evidence_dir"
    export BASH_ENV="$original_bash_env"
    export G5C_ARTIFACT_CAPTURE_ROOT="$original_capture_root"
    export G5C_ARTIFACT_PATHS="$original_paths_file"
    export G5C_ARTIFACT_NEGATIVE_PATHS="$original_negative_paths_file"
    export G5C_ARTIFACT_TMP_ROOT="$original_tmp_root"
    command rm -rf -- "$stale_evidence"
    mkdir -p "$capture_source"
    printf '(module (func $escape))\n' > "$escape_source"
    BASH_ENV="$BASH_ENV" \
        G5C_ARTIFACT_CAPTURE_ROOT="$capture_root" \
        G5C_ARTIFACT_PATHS="$evidence_dir/artifact-paths.log" \
        G5C_ARTIFACT_NEGATIVE_PATHS="$evidence_dir/negative-artifact-paths.log" \
        G5C_ARTIFACT_TMP_ROOT="$evidence_dir/tmp" \
        bash -c 'rm -f -- "$1"' bash "$escape_source"
    if compgen -G "$evidence_dir/capture-escape.wat*" >/dev/null; then
        printf 'self-test failed: artifact capture escaped its root\n' >&2
        return 1
    fi
    printf '(module (func $captured))\n' > "$capture_source/captured.wat"
    printf '(module (import "env" "f" (func (param (ref null 0)))))\n' > "$capture_source/gc-import.wat"
    BASH_ENV="$BASH_ENV" \
        G5C_ARTIFACT_CAPTURE_ROOT="$capture_root" \
        G5C_ARTIFACT_PATHS="$evidence_dir/artifact-paths.log" \
        G5C_ARTIFACT_NEGATIVE_PATHS="$evidence_dir/negative-artifact-paths.log" \
        G5C_ARTIFACT_TMP_ROOT="$evidence_dir/tmp" \
        bash -c 'rm -rf -- "$1"' bash "$capture_source"
    if [[ ! -s "$capture_root/self-capture-source/captured.wat" ]] || \
        ! rg -Fxq "$capture_root/self-capture-source/captured.wat" \
            "$evidence_dir/artifact-paths.log"; then
        printf 'self-test failed: artifact capture did not preserve a removed WAT\n' >&2
        return 1
    fi
    if [[ ! -s "$capture_root/self-capture-source/gc-import.wat" ]] || \
        ! rg -Fxq "$capture_root/self-capture-source/gc-import.wat" \
            "$evidence_dir/negative-artifact-paths.log"; then
        printf 'self-test failed: injected gc-import negative artifact was not preserved and classified\n' >&2
        return 1
    fi
    printf '(module (import "env" "f" (func (param i32))) (func $x))\n' > "$artifact"
    profile=S
    if ! check_profile_artifacts; then
        printf 'self-test failed: clean artifact was rejected\n' >&2
        return 1
    fi
    local external_clean="${evidence_dir}.external-clean.wat"
    printf '(module (func $external-clean))\n' > "$external_clean"
    printf '%s\n' "$external_clean" > "$evidence_dir/artifact-paths.log"
    if check_common_artifacts; then
        printf 'self-test failed: external clean artifact was accepted\n' >&2
        command rm -f -- "$external_clean"
        return 1
    fi
    command rm -f -- "$external_clean"

    # Some gates print repository-relative temporary paths with the leading
    # repository prefix omitted (/.tmp/...). Accept that spelling only when
    # it maps back into the current evidence root.
    alias_root=$(mktemp -d "$ROOT/.tmp/g5c-alias-self.XXXXXX")
    alias_outside_root=$(mktemp -d "$ROOT/.tmp/g5c-alias-outside.XXXXXX")
    alias_artifact="$alias_root/tmp/alias.wat"
    alias_outside_path="$alias_outside_root/outside.wat"
    mkdir -p "$alias_root/tmp" "$alias_root/artifacts"
    printf '(module (func $alias))\n' > "$alias_artifact"
    printf '(module (func $outside))\n' > "$alias_outside_path"
    alias_root_rel=${alias_root#"$ROOT/.tmp/"}
    [[ -n "$alias_root_rel" && "$alias_root_rel" != "$alias_root" ]] || {
        printf 'self-test failed: could not derive /.tmp alias path\n' >&2
        command rm -rf -- "$alias_root" "$alias_outside_root"
        return 1
    }
    local saved_evidence_dir="$evidence_dir"
    local saved_capture_root="$G5C_ARTIFACT_CAPTURE_ROOT"
    local saved_paths_file="$G5C_ARTIFACT_PATHS"
    local saved_negative_paths_file="$G5C_ARTIFACT_NEGATIVE_PATHS"
    local saved_reference_paths_file="$G5C_ARTIFACT_REFERENCE_PATHS"
    local saved_tmp_root="$G5C_ARTIFACT_TMP_ROOT"
    evidence_dir="$alias_root"
    G5C_ARTIFACT_CAPTURE_ROOT="$alias_root/artifacts"
    G5C_ARTIFACT_PATHS="$alias_root/artifact-paths.log"
    G5C_ARTIFACT_NEGATIVE_PATHS="$alias_root/negative-artifact-paths.log"
    G5C_ARTIFACT_REFERENCE_PATHS="$alias_root/reference-artifact-paths.log"
    G5C_ARTIFACT_TMP_ROOT="$alias_root/tmp"
    : > "$G5C_ARTIFACT_PATHS"
    printf '/.tmp/%s/tmp/alias.wat\n' "$alias_root_rel" > "$G5C_ARTIFACT_PATHS"
    profile=S
    if ! check_common_artifacts; then
        printf 'self-test failed: safe /.tmp alias was rejected\n' >&2
        evidence_dir="$saved_evidence_dir"
        G5C_ARTIFACT_CAPTURE_ROOT="$saved_capture_root"
        G5C_ARTIFACT_PATHS="$saved_paths_file"
        G5C_ARTIFACT_NEGATIVE_PATHS="$saved_negative_paths_file"
        G5C_ARTIFACT_REFERENCE_PATHS="$saved_reference_paths_file"
        G5C_ARTIFACT_TMP_ROOT="$saved_tmp_root"
        command rm -rf -- "$alias_root" "$alias_outside_root"
        return 1
    fi
    alias_outside_path="/.tmp/${alias_outside_root#"$ROOT/.tmp/"}/outside.wat"
    printf '%s\n' "$alias_outside_path" > "$G5C_ARTIFACT_PATHS"
    if check_common_artifacts; then
        printf 'self-test failed: /.tmp alias outside evidence root was accepted\n' >&2
        evidence_dir="$saved_evidence_dir"
        G5C_ARTIFACT_CAPTURE_ROOT="$saved_capture_root"
        G5C_ARTIFACT_PATHS="$saved_paths_file"
        G5C_ARTIFACT_NEGATIVE_PATHS="$saved_negative_paths_file"
        G5C_ARTIFACT_REFERENCE_PATHS="$saved_reference_paths_file"
        G5C_ARTIFACT_TMP_ROOT="$saved_tmp_root"
        command rm -rf -- "$alias_root" "$alias_outside_root"
        return 1
    fi
    evidence_dir="$saved_evidence_dir"
    G5C_ARTIFACT_CAPTURE_ROOT="$saved_capture_root"
    G5C_ARTIFACT_PATHS="$saved_paths_file"
    G5C_ARTIFACT_NEGATIVE_PATHS="$saved_negative_paths_file"
    G5C_ARTIFACT_REFERENCE_PATHS="$saved_reference_paths_file"
    G5C_ARTIFACT_TMP_ROOT="$saved_tmp_root"
    command rm -rf -- "$alias_root" "$alias_outside_root"
    printf '%s\n' "$artifact" > "$evidence_dir/artifact-paths.log"
    printf 'parse-core\n' > "$evidence_dir/g5a-h-self.log"
    profile=H
    if check_profile_artifacts; then
        printf 'self-test failed: incomplete H Component steps were accepted\n' >&2
        return 1
    fi
    printf '%s\n' \
        '+ /tool parse-core /tmp/h-input.wat -o /tmp/h-core.wasm' \
        '+ /tool embed-component /tmp/h-input.wit /tmp/h-core.wasm probe --features none -o /tmp/h-embedded.wasm' \
        '+ /tool new-component /tmp/h-embedded.wasm -o /tmp/h-component.wasm' \
        '+ /tool validate-component /tmp/h-component.wasm' > "$evidence_dir/g5a-h-self.log"
    if ! check_profile_artifacts; then
        printf 'self-test failed: complete H Component steps were rejected\n' >&2
        return 1
    fi
    mkdir -p "$test_dir/h-input-package"
    printf '%s\n' \
        '+ /tool parse-core /tmp/h-input.wat -o /tmp/h-core.wasm' \
        "+ /tool embed-component $test_dir/h-input-package /tmp/h-core.wasm probe --features none -o /tmp/h-embedded.wasm" \
        '+ /tool new-component /tmp/h-embedded.wasm -o /tmp/h-component.wasm' \
        '+ /tool validate-component /tmp/h-component.wasm' > "$evidence_dir/g5a-h-self.log"
    if ! check_profile_artifacts; then
        printf 'self-test failed: directory-form H Component steps were rejected\n' >&2
        return 1
    fi
    printf '%s\n' \
        '+ /tool parse-core /tmp/h-input.wat -o /tmp/h-core.wasm' \
        '+ /tool embed-component /tmp/h-input.wit /tmp/other.wasm probe --features none -o /tmp/h-embedded.wasm' \
        '+ /tool new-component /tmp/h-embedded.wasm -o /tmp/h-component.wasm' \
        '+ /tool validate-component /tmp/h-component.wasm' > "$evidence_dir/g5a-h-self.log"
    if check_h_component_steps; then
        printf 'self-test failed: unbound H Component artifact chain was accepted\n' >&2
        return 1
    fi
    printf '%s\n' "$tracked_arc_artifact" > "$evidence_dir/reference-artifact-paths.log"
    if check_reference_artifacts; then
        printf 'self-test failed: tracked ARC artifact bypassed content checks\n' >&2
        return 1
    fi
    rm -f -- "$evidence_dir/reference-artifact-paths.log"
    printf '(module\n(type $x (struct))\n(import "env" "f" (func (param (ref null $x))))\n)\n' > "$test_dir/forbidden.wat"
    printf '%s\n' "$test_dir/forbidden.wat" > "$evidence_dir/artifact-paths.log"
    if check_common_artifacts; then
        printf 'self-test failed: forbidden canonical import ref was accepted\n' >&2
        return 1
    fi
    "$TOOLCHAIN_BIN" parse-core "$test_dir/forbidden.wat" -o "$test_dir/forbidden.component.wasm"
    rm -f -- "$test_dir/forbidden.wat"
    printf '%s\n' "$test_dir/forbidden.component.wasm" > "$evidence_dir/artifact-paths.log"
    if check_common_artifacts; then
        printf 'self-test failed: valid binary forbidden canonical import ref was accepted\n' >&2
        return 1
    fi
    printf 'not-a-wasm-component\n' > "$test_dir/binary.component.wasm"
    printf '%s\n' "$test_dir/binary.component.wasm" > "$evidence_dir/artifact-paths.log"
    if check_common_artifacts; then
        printf 'self-test failed: invalid binary artifact was accepted\n' >&2
        return 1
    fi
    rm -f -- "$test_dir/binary.component.wasm" "$test_dir/forbidden.component.wasm" \
        "$evidence_dir/forbidden.component.wasm.printed.wat"
    printf '%s\n' \
        '(module' \
        '  (type $forbidden (func (param (ref null 0))))' \
        '  (import "env" "f" (func (type $forbidden)))' \
        ')' > "$test_dir/named-forbidden.wat"
    printf '%s\n' "$test_dir/named-forbidden.wat" > "$evidence_dir/artifact-paths.log"
    if check_common_artifacts; then
        printf 'self-test failed: named forbidden canonical import ref was accepted\n' >&2
        return 1
    fi
    rm -f -- "$test_dir/named-forbidden.wat"
    printf '%s\n' \
        '(module' \
        '  (type (;0;) (func (param i32)))' \
        '  (type (;1;) (func (param (ref null $later))))' \
        '  (import "env" "safe" (func (type 0)))' \
        '  (table 1 1 (ref null $later))' \
        ')' > "$test_dir/unrelated-ref.wat"
    printf '%s\n' "$test_dir/unrelated-ref.wat" > "$evidence_dir/artifact-paths.log"
    if ! check_common_artifacts; then
        printf 'self-test failed: unrelated later ref was treated as imported ref\n' >&2
        return 1
    fi
    rm -f -- "$test_dir/forbidden.wat" "$test_dir/forbidden.component.wasm" "$test_dir/binary.component.wasm" \
        "$test_dir/unrelated-ref.wat" "$evidence_dir/forbidden.component.wasm.printed.wat"
    rm -f -- "$evidence_dir/artifact-paths.log"
    if check_common_artifacts; then
        printf '%s\n' "$test_dir/missing.wat" > "$evidence_dir/artifact-paths.log"
        if check_common_artifacts; then
            printf 'self-test failed: missing artifact was accepted\n' >&2
            return 1
        fi
    fi
    rm -f -- "$evidence_dir/artifact-paths.log"
    profile=A
    row=future_stream_frames
    printf '%s\n' \
        'Do bounded async GC frame/table component passed: fixture=two-await-component.do' \
        > "$evidence_dir/g5a-test_gc_async_frame_component.log"
    printf '%s\n' \
        'future lifecycle case=pending pending-polls=4 external-wakes=4 completions=4' \
        'future lifecycle case=error host-errors=1 completions=0' \
        'future lifecycle case=cancel host-calls=1 cancelled=1' \
        'future lifecycle case=early-drop host-calls=0 cancelled=1' \
        'future lifecycle case=repeat runs=2 pending-polls=8 external-wakes=8 completions=8' \
        'future lifecycle case=ready status=unsupported-sync-completion backend=gc' \
        'future lifecycle case=ready status=unsupported-sync-completion backend=linear' \
        'GC/linear Future frame equivalence passed rows=1 ready=unsupported-sync-completion pending-polls=4 external-wakes=4 completions=4' \
        > "$evidence_dir/g5b-test_gc_async_frame_equivalence.log"
    if ! check_profile_artifacts; then
        printf 'self-test failed: positive Future A profile was rejected\n' >&2
        return 1
    fi
    awk '!/^GC\/linear Future frame equivalence passed /' \
        "$evidence_dir/g5b-test_gc_async_frame_equivalence.log" \
        > "$test_dir/future-equivalence-incomplete.log"
    mv -- "$test_dir/future-equivalence-incomplete.log" \
        "$evidence_dir/g5b-test_gc_async_frame_equivalence.log"
    if check_profile_artifacts; then
        printf 'self-test failed: incomplete Future lifecycle was accepted\n' >&2
        return 1
    fi
    row=resource_terminal_cleanup
    printf '%s\n' \
        'Do bounded GC resource terminal cleanup passed: fixture=async-resource-result-component.do' \
        'resource lifecycle case=ready backend=gc request consumed=2 response create=2 response drop=2 table-empty=true' \
        'resource lifecycle case=ready backend=linear request consumed=2 response create=2 response drop=2 table-empty=true' \
        'resource lifecycle case=pending backend=gc request consumed=2 response create=2 response drop=2 table-empty=true' \
        'resource lifecycle case=pending backend=linear request consumed=2 response create=2 response drop=2 table-empty=true' \
        'resource lifecycle case=error backend=gc request consumed=2 response create=0 response drop=0 table-empty=true' \
        'resource lifecycle case=error backend=linear request consumed=2 response create=0 response drop=0 table-empty=true' \
        'resource lifecycle case=repeat backend=gc request consumed=4 response create=4 response drop=4 table-empty=true' \
        'resource lifecycle case=repeat backend=linear request consumed=4 response create=4 response drop=4 table-empty=true' \
        > "$evidence_dir/g5a-test_gc_resource_terminal_cleanup.log"
    printf '%s\n' \
        'resource lifecycle case=cancel backend=gc request consumed=1 pending polls=1 pending future drops=1 response create=0 response drop=0 table-empty=true' \
        'resource lifecycle case=cancel backend=linear request consumed=1 pending polls=1 pending future drops=1 response create=0 response drop=0 table-empty=true' \
        'resource lifecycle case=early-drop backend=gc request consumed=0 pending polls=0 pending future drops=0 response create=0 response drop=0 table-empty=true' \
        'resource lifecycle case=early-drop backend=linear request consumed=0 pending polls=0 pending future drops=0 response create=0 response drop=0 table-empty=true' \
        'resource Result cancellation GC/linear equivalence passed' \
        > "$evidence_dir/g5b-test_rust_resource_cancellation_shape.log"
    if ! check_profile_artifacts; then
        printf 'self-test failed: positive resource A profile was rejected\n' >&2
        return 1
    fi
    awk '!/^resource lifecycle case=cancel /' \
        "$evidence_dir/g5b-test_rust_resource_cancellation_shape.log" \
        > "$test_dir/resource-cancel-incomplete.log"
    mv -- "$test_dir/resource-cancel-incomplete.log" \
        "$evidence_dir/g5b-test_rust_resource_cancellation_shape.log"
    if check_profile_artifacts; then
        printf 'self-test failed: incomplete cancellation evidence was accepted\n' >&2
        return 1
    fi
    local outside_artifact="$ROOT/.tmp/g5c-self-test-$$.wat"
    printf '(module (func $__arc_self_test))\n' > "$outside_artifact"
    printf '%s\n' "$outside_artifact" > "$evidence_dir/artifact-paths.log"
    profile=S
    if check_profile_artifacts; then
        printf 'self-test failed: ARC artifact was accepted\n' >&2
        rm -f -- "$outside_artifact"
        return 1
    fi
    rm -f -- "$outside_artifact"
    printf 'row runner profile/artifact self-tests passed\n'
    exit 0
}

install_artifact_capture
if ((self_test)); then
    run_self_tests
fi

verify_paths g5a_fixture "$g5a_sources"
verify_paths g5a_probe "$g5a_probes"
verify_paths g5b_evidence "$g5b_evidence"

run_gate arc_inventory bash "$ROOT/src/build/test/check_gc_arc_inventory.sh" --post-cutover
run_gate default_build bash "$ROOT/src/build/test/check_gc_default_build_gate.sh"
run_gate migration_evidence bash "$ROOT/src/build/test/check_gc_migration_evidence_test.sh"
expected_pending_rows=$(awk -F '\t' '
    index($0, "<<\047ROWS\047") { in_rows = 1; next }
    $0 == "ROWS" { in_rows = 0; next }
    in_rows && NF == 9 && ($2 == "pending" || $5 == "pending" || $7 == "pending") {
        count++
    }
    END { print count + 0 }
' "$INVENTORY_SCRIPT")
expected_inventory_summary="summary complete_rows=15 pending_rows=$expected_pending_rows"
printf 'inventory_expected_exit=1\ninventory_expected_summary=%s\n' \
    "$expected_inventory_summary" >> "$commands_log"
run_gate_expected inventory_status 1 bash "$INVENTORY_SCRIPT"
check_inventory_status_log "$evidence_dir/inventory_status.log" "$expected_pending_rows"
printf 'inventory_actual_summary=%s\n' \
    "$(rg '^summary complete_rows=[0-9]+ pending_rows=[0-9]+$' "$evidence_dir/inventory_status.log")" >> "$commands_log"

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
        if [[ "$profile" == H ]]; then
            run_gate "$label-$(basename "$path" .sh)" bash -x "$ROOT/$path"
        else
            run_gate "$label-$(basename "$path" .sh)" bash "$ROOT/$path"
        fi
    done
}

run_path_list g5a "$g5a_probes"
run_path_list g5b "$g5b_evidence"
check_profile_artifacts

toolchain_versions=$(jq -r '[.wasm_tools,.wasmtime] | map(.name + "=" + .version + " sha256=" + .sha256) | join("; ")' "$LOCK_FILE")
command_results=$(awk '/ expected_exit=/{printf "%s; ", $0}' "$commands_log")

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
toolchain_versions=$toolchain_versions
command_results=$command_results
result=passed
EOF
printf 'row=%s profile=%s result=passed summary=%s\n' "$row" "$profile" "$summary_file"
