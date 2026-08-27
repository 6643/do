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
nested_structs	complete	examples/gc-p3-runtime/nested-managed-struct.do,examples/gc-p3-runtime/two-level-nested-field-path.do,examples/gc-p3-runtime/three-level-nested-field-path.do,examples/gc-p3-runtime/four-level-nested-field-path.do,examples/gc-p3-runtime/five-level-nested-field-path.do	examples/gc-p3-runtime/test_do_gc_nested_managed_struct.sh,examples/gc-p3-runtime/test_do_gc_two_level_nested_field_path.sh,examples/gc-p3-runtime/test_do_gc_three_level_nested_field_path.sh,examples/gc-p3-runtime/test_do_gc_four_level_nested_field_path.sh,examples/gc-p3-runtime/test_do_gc_five_level_nested_field_path.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: direct local child @set/direct @get and bounded one-/two-/three-/four-/five-level nested scalar field paths are admitted; deeper/other nested aggregate shapes and producers fail as UnsupportedGcSyncProducer, UnsupportedGcSyncExpression, or UnsupportedGcSyncType
tuple_storage	complete	examples/gc-p3-runtime/managed-tuple-text-bytes.do	examples/gc-p3-runtime/test_do_gc_managed_tuple_text_bytes.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: direct Tuple<text,[u8]> get/rewrite with one byte-list @set is admitted; local tuple bindings fail as UnknownGcSyncLocal and other Tuple/storage shapes fail as UnsupportedGcSyncExpression or UnsupportedGcSyncType
unions	complete	examples/gc-p3-runtime/gc-payload-union.do	examples/gc-p3-runtime/test_do_gc_payload_union.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: bounded Unit | Bytes([u8]) carrier and direct [u8] | Error | nil call/tag comparison now have typed GC evidence, including synchronous defer and @len; @is/binding and general payload unions remain outside admission
generic_calls	complete	examples/gc-p3-runtime/generic-managed-identity.do	examples/gc-p3-runtime/test_do_gc_generic_managed_identity.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: resolved generic managed identity has typed GC and compiled-test equivalence evidence; generic field-update, layout instantiation, resources, and unresolved bindings remain outside admission
imports	complete	examples/gc-p3-runtime/imported-text-identity.do,examples/gc-p3-runtime/imported_text_helper.do	examples/gc-p3-runtime/test_do_gc_imported_text_identity.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: imported managed sync identity has file-backed GC and ARC equivalence evidence; host/WIT, async, and unsupported module graphs remain outside admission
host_wit_marshalling	complete	doc/wit/gc_descriptor_manifest.json,examples/gc-p3-runtime/wasi-random-gc-lift-package/worlds.wit,examples/gc-p3-runtime/marshal-record-assembly.wit,examples/gc-p3-runtime/marshal-record-host.wit,examples/gc-p3-runtime/marshal-record-lower-assembly.wit,examples/gc-p3-runtime/marshal-record-indirect-lower-assembly.wit,examples/gc-p3-runtime/marshal-record-lower-manifest-source.wit,doc/wit/gc_marshal_record_lower_imports.wit,examples/gc-p3-runtime/marshal-record-lift-manifest-source.wit,doc/wit/gc_marshal_record_lift_imports.wit,examples/gc-p3-runtime/marshal-record-mixed-lift-manifest-source.wit,doc/wit/gc_marshal_record_mixed_lift_imports.wit,examples/gc-p3-runtime/marshal-record-mixed-lift-assembly.wit,examples/gc-p3-runtime/marshal-record-mixed-lower-manifest-source.wit,doc/wit/gc_marshal_record_mixed_lower_imports.wit,examples/gc-p3-runtime/marshal-record-mixed-lower-assembly.wit,examples/gc-p3-runtime/marshal-record-mixed-lower-arc.core.wat,examples/gc-p3-runtime/ordinary-host-mixed-lower-call.do,examples/gc-p3-runtime/marshal-record-indirect-lower-manifest-source.wit,doc/wit/gc_marshal_record_indirect_lower_imports.wit,examples/gc-p3-runtime/marshal-record-nested-lift-manifest-source.wit,doc/wit/gc_marshal_record_nested_lift_imports.wit,examples/gc-p3-runtime/marshal-record-nested-lift-assembly.wit,examples/gc-p3-runtime/marshal-record-nested-lift-deep-manifest-source.wit,doc/wit/gc_marshal_record_nested_lift_deep_imports.wit,examples/gc-p3-runtime/marshal-record-nested-lift-deep-assembly.wit,examples/gc-p3-runtime/marshal-record-nested-lift-deeper-manifest-source.wit,doc/wit/gc_marshal_record_nested_lift_deeper_imports.wit,examples/gc-p3-runtime/marshal-record-nested-lift-deeper-assembly.wit,examples/gc-p3-runtime/marshal-record-nested-lower-manifest-source.wit,doc/wit/gc_marshal_record_nested_lower_imports.wit,examples/gc-p3-runtime/marshal-record-nested-lower-assembly.wit,examples/gc-p3-runtime/marshal-record-nested-lower-deep-manifest-source.wit,doc/wit/gc_marshal_record_nested_lower_deep_imports.wit,examples/gc-p3-runtime/marshal-record-nested-lower-deep-assembly.wit,examples/gc-p3-runtime/marshal-record-nested-lower-deeper-manifest-source.wit,doc/wit/gc_marshal_record_nested_lower_deeper_imports.wit,examples/gc-p3-runtime/marshal-record-nested-lower-deeper-assembly.wit,examples/gc-p3-runtime/marshal-record-managed-lift-manifest-source.wit,doc/wit/gc_marshal_record_managed_lift_imports.wit,examples/gc-p3-runtime/marshal-record-managed-lift-assembly.wit,examples/gc-p3-runtime/marshal-record-managed-lower-multi-manifest-source.wit,doc/wit/gc_marshal_record_managed_lower_multi_imports.wit,examples/gc-p3-runtime/marshal-record-managed-lower-multi-assembly.wit,examples/gc-p3-runtime/marshal-record-managed-lower-multi-arc.core.wat	examples/gc-p3-runtime/test_gc_wasi_random_list_lift.sh,examples/gc-p3-runtime/test_gc_marshal_record_component.sh,examples/gc-p3-runtime/test_gc_marshal_record_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_lower_component.sh,examples/gc-p3-runtime/test_gc_marshal_record_lower_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_lower_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_lift_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_mixed_lift_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deep_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deep_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_host.sh,examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_host.sh,examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_negative.sh	complete	examples/gc-p3-runtime/test_gc_wasi_random_list_lift_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_lower_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_lower_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_lift_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_mixed_lift_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deep_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deep_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_equivalence.sh,examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_equivalence.sh	pending	-	current implementation record: the manifest-backed WASI random list<u8> lift, text lower, list<u32> lower/lift, flat scalar-record lower/lift, mixed scalar-record lift, scalar-plus-text managed-field record lift, 17-field indirect scalar-record lower, two-level nested scalar-record lift/lower, the three-level nested scalar-record lower, the three-level nested scalar-record lift, and the four-level nested scalar-record lower/lift now have pinned Component gates and independent GC/ARC canonical-boundary equivalence rows; bounded parser-backed mixed scalar-record lower also has measured canonical ABI, no-GC-reference boundary checks, pinned Component assembly, generated host execution, and GC/flat equivalence; arbitrary/deeper/general aggregates, nested aggregate shapes beyond these scalar records, indirect layouts beyond the pinned 17-field shape, text/list record lower beyond the private managed-field descriptors; the exact C14, C15-B/C15-D, C16-C/C16-D, and mixed scalar-record lower default routes are closed, while general aggregates, async/resource paths, and G5c cutover remain pending
host_wit_marshalling_managed_record_lower	complete	examples/gc-p3-runtime/marshal-record-managed-lower-manifest-source.wit,examples/gc-p3-runtime/marshal-record-managed-lower-assembly.wit,examples/gc-p3-runtime/marshal-record-managed-lower-multi-manifest-source.wit,doc/wit/gc_marshal_record_managed_lower_multi_imports.wit,examples/gc-p3-runtime/marshal-record-managed-lower-multi-assembly.wit,examples/gc-p3-runtime/marshal-record-managed-lower-multi-arc.core.wat	examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_host.sh	complete	examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_equivalence.sh	pending	-	current implementation record: the exact manifest-backed root records {u32,string} and {u32,string,string} lower now also use the ordinary default route; general managed record lower, async/resource paths, and G5c cutover remain pending
sync_control_flow	complete	examples/gc-p3-runtime/text-branch.do	examples/gc-p3-runtime/test_do_gc_text_branch.sh	complete	src/build/test/check_gc_semantic_equivalence.sh	pending	-	current implementation record: parsed text branch join and bounded synchronous defer are admitted; loop and other control flow fail as UnsupportedGcSyncControl or UnsupportedGcSyncStatement
future_stream_frames	complete	examples/p3-runtime/two-await-component.do	examples/gc-p3-runtime/test_gc_async_frame_component.sh	complete	examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh	pending	-	current implementation record: bounded --p3-wait-for-component GC-traced Future frame/table path has GC/linear backend-neutral equivalence evidence for two sequential Future<nil> awaits; ordinary GC sync admission remains UnsupportedGcSyncAsync, while generic async lowering, Stream/general async, and G5c remain pending
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

# Additional private evidence attached to the pending host_wit_marshalling G5c
# boundary. Keep this separate from the TSV status fields so the inventory
# remains 15 rows and continues to report complete_rows=15/pending_rows=15.
host_wit_byte_list_evidence='examples/gc-p3-runtime/marshal-record-byte-list-lower-manifest-source.wit,doc/wit/gc_marshal_record_byte_list_lower_imports.wit,examples/gc-p3-runtime/marshal-record-byte-list-lower-assembly.wit,examples/gc-p3-runtime/marshal-record-byte-list-lower-arc.core.wat,examples/gc-p3-runtime/ordinary-host-record-byte-list-lower-call.do,examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_byte_list_lower.rs,examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_byte_list_lower_equivalence.rs,examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lower_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lower_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lower_negative.sh,src/build/test/compile_ok/592_gc_wit_record_byte_list_lower_host_boundary.do,src/build/test/compile_err/595_gc_wit_record_byte_list_lower_host_boundary_async.do,src/build/test/compile_err/595_gc_wit_record_byte_list_lower_host_boundary_async.expect,src/build/test/compile_err/596_gc_wit_record_byte_list_lower_host_boundary_locator.do,src/build/test/compile_err/596_gc_wit_record_byte_list_lower_host_boundary_locator.expect,src/build/test/compile_err/597_gc_wit_record_byte_list_lower_host_boundary_member.do,src/build/test/compile_err/597_gc_wit_record_byte_list_lower_host_boundary_member.expect,src/build/test/compile_err/598_gc_wit_record_byte_list_lower_host_boundary_reordered.do,src/build/test/compile_err/598_gc_wit_record_byte_list_lower_host_boundary_reordered.expect,src/build/test/compile_err/599_gc_wit_record_byte_list_lower_host_boundary_u16.do,src/build/test/compile_err/599_gc_wit_record_byte_list_lower_host_boundary_u16.expect,src/build/test/compile_err/600_gc_wit_record_byte_list_lower_host_boundary_extra_field.do,src/build/test/compile_err/600_gc_wit_record_byte_list_lower_host_boundary_extra_field.expect,examples/gc-p3-runtime/marshal-record-byte-list-lift-manifest-source.wit,doc/wit/gc_marshal_record_byte_list_lift_imports.wit,examples/gc-p3-runtime/marshal-record-byte-list-lift-assembly.wit,examples/gc-p3-runtime/marshal-record-byte-list-lift-arc.core.wat,examples/gc-p3-runtime/ordinary-host-record-byte-list-lift-call.do,examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_byte_list_lift.rs,examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lift_manifest_host.sh,examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lift_manifest_equivalence.sh,examples/gc-p3-runtime/test_gc_marshal_record_byte_list_lift_negative.sh,src/build/test/compile_ok/615_gc_wit_record_byte_list_lift_host_boundary.do,src/build/test/compile_err/616_gc_wit_record_byte_list_lift_host_boundary_async.do,src/build/test/compile_err/616_gc_wit_record_byte_list_lift_host_boundary_async.expect,src/build/test/compile_err/617_gc_wit_record_byte_list_lift_host_boundary_locator.do,src/build/test/compile_err/617_gc_wit_record_byte_list_lift_host_boundary_locator.expect,src/build/test/compile_err/618_gc_wit_record_byte_list_lift_host_boundary_member.do,src/build/test/compile_err/618_gc_wit_record_byte_list_lift_host_boundary_member.expect,src/build/test/compile_err/619_gc_wit_record_byte_list_lift_host_boundary_reordered.do,src/build/test/compile_err/619_gc_wit_record_byte_list_lift_host_boundary_reordered.expect,src/build/test/compile_err/620_gc_wit_record_byte_list_lift_host_boundary_u32.do,src/build/test/compile_err/620_gc_wit_record_byte_list_lift_host_boundary_u32.expect,src/build/test/compile_err/621_gc_wit_record_byte_list_lift_host_boundary_extra_field.do,src/build/test/compile_err/621_gc_wit_record_byte_list_lift_host_boundary_extra_field.expect'

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
for evidence in ${host_wit_byte_list_evidence//,/ }; do
    if [ ! -f "$ROOT/$evidence" ]; then
        printf 'missing host_wit_marshalling byte-list evidence: %s\n' "$evidence" >&2
        failures=$((failures + 1))
    fi
done
if [ "$row_count" -ne 15 ]; then
    printf 'invalid inventory row count: rows=%d expected=15\n' "$row_count" >&2
    failures=$((failures + 1))
fi

printf 'summary complete_rows=%d pending_rows=%d\n' "$complete_rows" "$pending_rows"

if [ "$failures" -ne 0 ]; then exit 2; fi
if [ "$pending_rows" -ne 0 ]; then
    printf 'GC migration inventory is incomplete: pending G5a/G5b/G5c rows remain\n' >&2
    exit 1
fi
