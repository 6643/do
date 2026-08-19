#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

evidence_file_is_verified() {
    local file="$1"
    [ -f "$file" ] || return 1
    case "$file" in
        *.md)
            rg -q '^Verification Status: (verified|complete)$' "$file"
            ;;
        *.sh)
            rg -q '^# Verification Status: (verified|complete)$' "$file"
            ;;
        *)
            return 1
            ;;
    esac
}

if [ "${1:-}" = --check-evidence ]; then
    if [ "$#" -ne 2 ] || ! evidence_file_is_verified "$2"; then
        printf 'evidence is not verified: %s\n' "${2:-<missing>}" >&2
        exit 1
    fi
    printf 'verified evidence: %s\n' "$2"
    exit 0
fi

# TSV: path, G5a status, G5a source fixtures, G5a bash-invokable probe scripts,
# G5b status, G5b evidence, G5c status, G5c evidence, current implementation
# boundary record.
inventory=$(cat <<'ROWS'
text	complete	examples/gc-p3-runtime/text-identity.do,examples/gc-p3-runtime/text-identity-renamed.do,examples/gc-p3-runtime/text-branch.do	examples/gc-p3-runtime/test_do_gc_text_identity.sh,examples/gc-p3-runtime/test_do_gc_text_identity_renamed.sh,examples/gc-p3-runtime/test_do_gc_text_branch.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: UnsupportedGcSyncExpression outside parsed text identity/branch admission
[u8]	complete	examples/gc-p3-runtime/list-set.do,examples/gc-p3-runtime/parameterized-list-set.do,examples/gc-p3-runtime/list-literal.do,examples/gc-p3-runtime/list-put.do	examples/gc-p3-runtime/test_do_gc_list_set.sh,examples/gc-p3-runtime/test_do_gc_parameterized_list_set.sh,examples/gc-p3-runtime/test_do_gc_list_literal.sh,examples/gc-p3-runtime/test_do_gc_list_put.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: UnsupportedGcSyncExpression or UnsupportedGcSyncType
other_lists	complete	examples/gc-p3-runtime/u32-list-literal.do,examples/gc-p3-runtime/u32-list-set.do,examples/gc-p3-runtime/i16-list-literal.do,examples/gc-p3-runtime/i16-list-set.do,examples/gc-p3-runtime/i32-list-literal.do,examples/gc-p3-runtime/i32-list-set.do,examples/gc-p3-runtime/i64-list-literal.do,examples/gc-p3-runtime/i64-list-set.do,examples/gc-p3-runtime/f32-list-literal.do,examples/gc-p3-runtime/f64-list-literal.do,examples/gc-p3-runtime/f32-list-set.do,examples/gc-p3-runtime/f64-list-set.do,examples/gc-p3-runtime/bool-list-set.do,examples/gc-p3-runtime/i8-list.do,examples/gc-p3-runtime/u16-list.do,examples/gc-p3-runtime/u64-list.do,examples/gc-p3-runtime/isize-list.do,examples/gc-p3-runtime/usize-list.do,examples/gc-p3-runtime/text-list.do,examples/gc-p3-runtime/text-list-put.do,examples/gc-p3-runtime/nested-byte-list.do,examples/gc-p3-runtime/nested-byte-list-put.do,examples/gc-p3-runtime/scalar-list-put.do,examples/gc-p3-runtime/inferred-list-storage.do,examples/gc-p3-runtime/inferred-u32-list-storage.do	examples/gc-p3-runtime/test_do_gc_u32_list_literal.sh,examples/gc-p3-runtime/test_do_gc_u32_list_set.sh,examples/gc-p3-runtime/test_do_gc_i16_list_literal.sh,examples/gc-p3-runtime/test_do_gc_i16_list_set.sh,examples/gc-p3-runtime/test_do_gc_i32_list_literal.sh,examples/gc-p3-runtime/test_do_gc_i32_list_set.sh,examples/gc-p3-runtime/test_do_gc_i64_list_literal.sh,examples/gc-p3-runtime/test_do_gc_f32_list_literal.sh,examples/gc-p3-runtime/test_do_gc_f64_list_literal.sh,examples/gc-p3-runtime/test_do_gc_f32_list_set.sh,examples/gc-p3-runtime/test_do_gc_f64_list_set.sh,examples/gc-p3-runtime/test_do_gc_bool_list_set.sh,examples/gc-p3-runtime/test_do_gc_remaining_scalar_lists.sh,examples/gc-p3-runtime/test_do_gc_text_list.sh,examples/gc-p3-runtime/test_do_gc_text_list_put.sh,examples/gc-p3-runtime/test_do_gc_nested_byte_list.sh,examples/gc-p3-runtime/test_do_gc_nested_byte_list_put.sh,examples/gc-p3-runtime/test_do_gc_scalar_list_put.sh,examples/gc-p3-runtime/test_do_gc_inferred_list_storage.sh,examples/gc-p3-runtime/test_do_gc_inferred_u32_list_storage.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: scalar list literal/fixed-index update and one-value @put slices for all registered scalar list types, bounded managed-element text-list @put, bounded inferred [u8]/[u32] body storage @put, and the bounded [[u8]] nested-list @put are admitted as G5a; spread/multi-value @put, dynamic producers, and other producer lists remain UnsupportedGcSyncType or UnsupportedGcSyncExpression
managed_struct_list_append	complete	examples/gc-p3-runtime/managed-struct-list.do	examples/gc-p3-runtime/test_do_gc_managed_struct_list.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: normal compiled-test routing now emits the bounded [Box] one-value @put path through typed GC; spread/multi-value producers, general nested producers, host/WIT, async/resource paths and G5c remain outside admission
managed_structs	complete	examples/gc-p3-runtime/managed-struct-payload.do,examples/gc-p3-runtime/managed-field-call-producer.do,examples/gc-p3-runtime/managed-text-field-call-producer.do,examples/gc-p3-runtime/managed-struct-payload-renamed.do,examples/gc-p3-runtime/managed-struct-preserve-field.do,examples/gc-p3-runtime/managed-struct-renamed.do,examples/gc-p3-runtime/managed-struct-set.do,examples/gc-p3-runtime/managed-struct-bool-field.do,examples/gc-p3-runtime/managed-struct-u32-field.do,examples/gc-p3-runtime/managed-struct-i16-field.do,examples/gc-p3-runtime/managed-struct-i32-field.do,examples/gc-p3-runtime/managed-struct-i64-field.do,examples/gc-p3-runtime/managed-struct-f32-field.do,examples/gc-p3-runtime/managed-struct-f64-field.do,examples/gc-p3-runtime/managed-struct-i8-field.do,examples/gc-p3-runtime/managed-struct-u16-field.do,examples/gc-p3-runtime/managed-struct-u64-field.do,examples/gc-p3-runtime/managed-struct-isize-field.do,examples/gc-p3-runtime/managed-struct-usize-field.do	examples/gc-p3-runtime/test_do_gc_managed_struct_payload.sh,examples/gc-p3-runtime/test_do_gc_managed_field_call_producer.sh,examples/gc-p3-runtime/test_do_gc_managed_text_field_call_producer.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_payload_renamed.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_preserve_field.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_renamed.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_set.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_bool_field.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_u32_field.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_i16_field.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_i32_field.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_i64_field.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_f32_field.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_f64_field.sh,examples/gc-p3-runtime/test_do_gc_managed_struct_remaining_scalar_fields.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: direct local/field-get and one direct single-return synchronous call are admitted for `[u8]`/`text` managed-field replacement; nested/multi-return/mismatched/async/host producers, nested paths, and resource-containing structs remain UnsupportedGcSyncProducer, UnsupportedGcSyncType, or UnsupportedGcSyncExpression
nested_structs	complete	examples/gc-p3-runtime/nested-managed-struct.do,examples/gc-p3-runtime/two-level-nested-field-path.do,examples/gc-p3-runtime/three-level-nested-field-path.do	examples/gc-p3-runtime/test_do_gc_nested_managed_struct.sh,examples/gc-p3-runtime/test_do_gc_two_level_nested_field_path.sh,examples/gc-p3-runtime/test_do_gc_three_level_nested_field_path.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: direct local child @set/direct @get and bounded one-/two-/three-level nested scalar field paths are admitted; a fourth managed segment, other nested aggregate shapes, and producers fail as UnsupportedGcSyncProducer, UnsupportedGcSyncExpression, or UnsupportedGcSyncType
tuple_storage	complete	examples/gc-p3-runtime/managed-tuple-text-bytes.do	examples/gc-p3-runtime/test_do_gc_managed_tuple_text_bytes.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: direct Tuple<text,[u8]> get/rewrite with one byte-list @set is admitted; local tuple bindings fail as UnknownGcSyncLocal and other Tuple/storage shapes fail as UnsupportedGcSyncExpression or UnsupportedGcSyncType
unions	complete	examples/gc-p3-runtime/gc-payload-union.do	examples/gc-p3-runtime/test_do_gc_payload_union.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: bounded Unit | Bytes([u8]) carrier and direct [u8] | Error | nil call/tag comparison now have typed GC evidence, including synchronous defer and @len; @is/binding and general payload unions remain outside admission
generic_calls	complete	examples/gc-p3-runtime/generic-managed-identity.do	examples/gc-p3-runtime/test_do_gc_generic_managed_identity.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: resolved generic managed identity has typed GC and compiled-test equivalence evidence; generic field-update, layout instantiation, resources, and unresolved bindings remain outside admission
imports	complete	examples/gc-p3-runtime/imported-text-identity.do,examples/gc-p3-runtime/imported_text_helper.do	examples/gc-p3-runtime/test_do_gc_imported_text_identity.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: imported managed sync identity has file-backed GC and ARC equivalence evidence; host/WIT, async, and unsupported module graphs remain outside admission
host_wit_marshalling	complete	examples/gc-p3-runtime/marshal-record-assembly.wit,examples/gc-p3-runtime/marshal-record-host.wit,examples/gc-p3-runtime/marshal-record-lower-assembly.wit,examples/gc-p3-runtime/marshal-record-indirect-lower-assembly.wit	examples/gc-p3-runtime/test_gc_marshal_record_component.sh,examples/gc-p3-runtime/test_gc_marshal_record_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_lower_component.sh,examples/gc-p3-runtime/test_gc_marshal_record_lower_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_host.sh	complete	examples/gc-p3-runtime/test_gc_marshal_record_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_lower_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_equivalence.sh	pending	-	current implementation record: bounded parser-backed scalar-record lift, flat scalar-record lower, and the pinned 17-field indirect scalar-record lower now have measured canonical ABI, no-GC-reference boundary checks, pinned Component assembly, generated host execution, and GC/flat equivalence; nested/general aggregates, indirect layouts beyond this shape, default host/WIT routing, and G5c cutover remain pending
sync_control_flow	complete	examples/gc-p3-runtime/text-branch.do	examples/gc-p3-runtime/test_do_gc_text_branch.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: parsed text branch join and bounded synchronous defer are admitted; loop and other control flow fail as UnsupportedGcSyncControl or UnsupportedGcSyncStatement
future_stream_frames	complete	examples/p3-runtime/two-await-component.do	examples/gc-p3-runtime/test_gc_async_frame_component.sh	pending	-	pending	-	current implementation record: bounded --p3-wait-for-component GC-traced Future frame/table path; ordinary GC sync admission remains UnsupportedGcSyncAsync
resource_terminal_cleanup	complete	examples/p3-runtime/async-resource-result-component.do	examples/gc-p3-runtime/test_gc_resource_terminal_cleanup.sh	complete	examples/p3-runtime/test_rust_resource_cancellation_shape.sh	pending	-	current implementation record: bounded GC async resource Result terminal paths and backend-neutral GC/linear cancellation observations are verified; ordinary GC sync admission remains UnsupportedGcSyncAggregate or UnsupportedGcSyncType, and G5c default routing remains pending
ROWS
)

failures=0
complete_rows=0
pending_rows=0
row_count=0
declare -A seen_paths=()
required_paths='text
[u8]
other_lists
managed_struct_list_append
managed_structs
nested_structs
tuple_storage
unions
generic_calls
imports
host_wit_marshalling
sync_control_flow
future_stream_frames
resource_terminal_cleanup'

check_evidence_files() {
    local path="$1" phase="$2" value="$3" linked
    if [ "$value" = - ]; then
        printf 'complete row lacks linked evidence: path=%s phase=%s\n' "$path" "$phase" >&2
        failures=$((failures + 1))
        return
    fi
    for linked in ${value//,/ }; do
        case "$linked" in
            /*|*' '*|*'..'*|*:*|'' )
                printf 'invalid evidence path: path=%s phase=%s evidence=%s\n' "$path" "$phase" "$linked" >&2
                failures=$((failures + 1))
                ;;
            *)
                if [ ! -f "$ROOT/$linked" ]; then
                    printf 'missing linked evidence: path=%s phase=%s evidence=%s\n' "$path" "$phase" "$linked" >&2
                    failures=$((failures + 1))
                elif ! evidence_file_is_verified "$ROOT/$linked"; then
                    printf 'unverified linked evidence: path=%s phase=%s evidence=%s\n' "$path" "$phase" "$linked" >&2
                    failures=$((failures + 1))
                fi
                ;;
        esac
    done
}

while IFS= read -r row; do
    row_count=$((row_count + 1))
    if [ -z "$row" ]; then
        printf 'blank inventory row: row=%d\n' "$row_count" >&2
        failures=$((failures + 1))
        continue
    fi
    IFS=$'\t' read -r -a fields <<< "$row"
    if [ "${#fields[@]}" -ne 9 ]; then
        printf 'invalid TSV field count: row=%d fields=%d expected=9\n' "$row_count" "${#fields[@]}" >&2
        failures=$((failures + 1))
        continue
    fi
    path=${fields[0]}; g5a=${fields[1]}; g5a_fixtures=${fields[2]}; g5a_probes=${fields[3]}
    g5b=${fields[4]}; g5b_evidence=${fields[5]}; g5c=${fields[6]}; g5c_evidence=${fields[7]}; boundary=${fields[8]}
    if [ -n "${seen_paths[$path]+x}" ]; then
        printf 'duplicate inventory path: path=%s\n' "$path" >&2
        failures=$((failures + 1))
    fi
    seen_paths[$path]=1
    case "$boundary" in
        'current implementation record: '*) ;;
        *) printf 'boundary is not a current implementation record: path=%s\n' "$path" >&2; failures=$((failures + 1)) ;;
    esac

    for value in "$g5a" "$g5b" "$g5c"; do
        case "$value" in
            complete|pending) ;;
            *) printf 'invalid status: path=%s status=%s\n' "$path" "$value" >&2; failures=$((failures + 1)) ;;
        esac
    done

    if [ "$g5a" = complete ]; then
        complete_rows=$((complete_rows + 1))
        if [ "$g5a_fixtures" = - ] || [ "$g5a_probes" = - ]; then
            printf 'complete row lacks linked G5a evidence: path=%s\n' "$path" >&2
            failures=$((failures + 1))
        fi
        for linked in ${g5a_fixtures//,/ } ${g5a_probes//,/ }; do
            case "$linked" in
                /*|*' '*|*'..'*|*:*|'' )
                    printf 'invalid G5a evidence path: path=%s evidence=%s\n' "$path" "$linked" >&2
                    failures=$((failures + 1))
                    ;;
                *)
                    if [ ! -f "$ROOT/$linked" ]; then
                        printf 'missing G5a evidence: path=%s evidence=%s\n' "$path" "$linked" >&2
                        failures=$((failures + 1))
                    fi
                    ;;
            esac
        done
    elif [ "$g5a_fixtures" != - ] || [ "$g5a_probes" != - ]; then
        printf 'pending row fabricates G5a evidence: path=%s\n' "$path" >&2
        failures=$((failures + 1))
    fi

    if [ "$g5b" = complete ]; then check_evidence_files "$path" G5b "$g5b_evidence"; elif [ "$g5b_evidence" != - ]; then printf 'pending row fabricates G5b evidence: path=%s\n' "$path" >&2; failures=$((failures + 1)); fi
    if [ "$g5c" = complete ]; then check_evidence_files "$path" G5c "$g5c_evidence"; elif [ "$g5c_evidence" != - ]; then printf 'pending row fabricates G5c evidence: path=%s\n' "$path" >&2; failures=$((failures + 1)); fi

    if [ "$g5a" = pending ] || [ "$g5b" = pending ] || [ "$g5c" = pending ]; then
        pending_rows=$((pending_rows + 1))
        printf 'pending path=%s g5a=%s g5b=%s g5c=%s boundary=%s\n' "$path" "$g5a" "$g5b" "$g5c" "$boundary"
    else
        printf 'complete path=%s g5a=%s g5b=%s g5c=%s\n' "$path" "$g5a" "$g5b" "$g5c"
    fi
done <<< "$inventory"

while IFS= read -r required; do
    if [ -z "${seen_paths[$required]+x}" ]; then
        printf 'missing required inventory path: path=%s\n' "$required" >&2
        failures=$((failures + 1))
    fi
done <<< "$required_paths"
if [ "$row_count" -ne 14 ]; then
    printf 'invalid inventory row count: rows=%d expected=14\n' "$row_count" >&2
    failures=$((failures + 1))
fi

printf 'summary complete_rows=%d pending_rows=%d\n' "$complete_rows" "$pending_rows"

if [ "$failures" -ne 0 ]; then exit 2; fi
if [ "$pending_rows" -ne 0 ]; then
    printf 'GC migration inventory is incomplete: pending G5a/G5b/G5c rows remain\n' >&2
    exit 1
fi
