#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATE="$ROOT_DIR/src/build/test/check_gc_g5c_residual_gate.sh"
EVIDENCE="$ROOT_DIR/examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh"

if ! rg -q 'test_gc_async_frame_equivalence\.sh' "$GATE"; then
    printf '[FAIL] G5c residual gate does not include bounded Future G5b equivalence\n' >&2
    exit 1
fi
if ! rg -q '^# Verification Status: (verified|complete)$' "$EVIDENCE"; then
    printf '[FAIL] bounded Future G5b evidence is not marked verified\n' >&2
    exit 1
fi

for gate in \
    test_gc_default_host_route_nested_record_deeper.sh \
    test_gc_default_host_route_nested_record_deeper_equivalence.sh \
    test_gc_default_host_route_nested_record_deeper_negative.sh \
    test_gc_default_host_route_mixed_lower_host.sh \
    test_gc_default_host_route_mixed_lower_equivalence.sh \
    test_gc_default_host_route_mixed_lower_negative.sh \
    test_gc_default_host_route_mixed_scalar_list_lower_host.sh \
    test_gc_default_host_route_mixed_scalar_list_lower_equivalence.sh \
    test_gc_default_host_route_mixed_scalar_list_lower_negative.sh \
    test_gc_default_host_route_mixed_text_u32_list_lower_host.sh \
    test_gc_default_host_route_mixed_text_u32_list_lower_equivalence.sh \
    test_gc_default_host_route_mixed_text_u32_list_lower_negative.sh \
    test_gc_marshal_record_byte_list_lower_manifest_host.sh \
    test_gc_marshal_record_byte_list_lower_manifest_equivalence.sh \
    test_gc_marshal_record_byte_list_lower_negative.sh \
    test_gc_marshal_record_byte_list_lift_manifest_host.sh \
    test_gc_marshal_record_byte_list_lift_manifest_equivalence.sh \
    test_gc_marshal_record_byte_list_lift_negative.sh \
    test_gc_marshal_record_u32_list_lift_manifest_host.sh \
    test_gc_marshal_record_u32_list_lift_manifest_equivalence.sh \
    test_gc_marshal_record_u32_list_lift_negative.sh \
    test_gc_marshal_record_mixed_text_u32_list_lift_manifest_host.sh \
    test_gc_marshal_record_mixed_text_u32_list_lift_manifest_equivalence.sh \
    test_gc_marshal_record_mixed_text_u32_list_lift_negative.sh \
    test_gc_marshal_record_mixed_text_byte_list_lift_manifest_host.sh \
    test_gc_marshal_record_mixed_text_byte_list_lift_manifest_equivalence.sh \
    test_gc_marshal_record_mixed_text_byte_list_lift_negative.sh \
    test_gc_marshal_record_mixed_text_two_u32_lists_lift_manifest_host.sh \
    test_gc_marshal_record_mixed_text_two_u32_lists_lift_manifest_equivalence.sh \
    test_gc_marshal_record_mixed_text_two_u32_lists_lift_negative.sh \
    test_gc_default_host_route_mixed_text_u32_list_lift_host.sh \
    test_gc_default_host_route_mixed_text_u32_list_lift_equivalence.sh \
    test_gc_default_host_route_mixed_text_u32_list_lift_negative.sh \
    test_gc_default_host_route_mixed_text_byte_list_lift_host.sh \
    test_gc_default_host_route_mixed_text_byte_list_lift_equivalence.sh \
    test_gc_default_host_route_mixed_text_byte_list_lift_negative.sh \
    test_gc_default_host_route_mixed_text_two_u32_lists_lift_host.sh \
    test_gc_default_host_route_mixed_text_two_u32_lists_lift_equivalence.sh \
    test_gc_default_host_route_mixed_text_two_u32_lists_lift_negative.sh \
    test_gc_two_u32_lists_lower_host.sh \
    test_gc_two_u32_lists_lower_equivalence.sh \
    test_gc_two_u32_lists_lower_negative.sh \
    test_gc_marshal_record_mixed_text_byte_u32_lists_lower_manifest_host.sh \
    test_gc_marshal_record_mixed_text_byte_u32_lists_lower_manifest_equivalence.sh \
    test_gc_marshal_record_mixed_text_byte_u32_lists_lower_negative.sh; do
    if ! rg -q "$gate" "$GATE"; then
        printf '[FAIL] G5c residual gate does not include %s\n' "$gate" >&2
        exit 1
    fi
done

printf '[PASS] G5c residual gate includes verified Future G5b, C14 nested-record, mixed-lower default-routes, mixed text/u32-list lift/lower, byte-list record lift, u32-list record-lift, two-u32-list lower, and mixed text/byte-u32-list lower gates\n'
