#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# All structured generated text must use the explicit-indent block helpers.
legacy_files=$(rg -l \
    'append_fmt_generated|alloc_fmt_generated|append_generated|alloc_generated' \
    "$ROOT_DIR/src" --glob '*.zig' || true)

if [[ -n "$legacy_files" ]]; then
    printf 'legacy generated-text helper references remain:\n%s\n' "$legacy_files" >&2
    exit 1
fi

# Every append_fmt implementation must delegate to the shared helper.  Keeping
# another std.fmt.allocPrint body silently creates a second formatting contract.
duplicate_fmt_impls=$(rg -l -U -P 'fn append_fmt\([^}]{0,800}?std\.fmt\.allocPrint' \
    "$ROOT_DIR/src" --glob '*.zig' | rg -v '/codegen_text\.zig$' || true)
if [[ -n "$duplicate_fmt_impls" ]]; then
    printf 'duplicate append_fmt implementations remain:\n%s\n' "$duplicate_fmt_impls" >&2
    exit 1
fi

# Keep the named-argument contract enforced by the shared API itself, not only
# by this source scan. All four formatted entry points must validate their
# argument type before rendering.
named_arg_guard_count=$(rg -n -F 'validate_named_format_args(@TypeOf(args));' \
    "$ROOT_DIR/src/build/codegen_text.zig" | wc -l | tr -d ' ')
if [[ "$named_arg_guard_count" -ne 4 ]]; then
    printf 'generated-text format helpers must keep four named-argument guards (found %s)\n' "$named_arg_guard_count" >&2
    exit 1
fi

unindexed_format_calls=$(rg -n -U -P \
    '(?:generated_text\.)?(?:append_fmt|alloc_fmt)\([^;\n]{0,600}?\{[sdifxXboc]\}' \
    "$ROOT_DIR/src" --glob '*.zig' || true)
if [[ -n "$unindexed_format_calls" ]]; then
    printf 'unindexed generated-text format placeholders remain:\n%s\n' "$unindexed_format_calls" >&2
    exit 1
fi

# Generated-text format tuples must use named fields.  This catches the
# positional form from both one-line and multiline calls, while allowing the
# empty tuple used by wrappers that have no format arguments.
positional_format_args=$(rg -n -U -P \
    '(?:append_fmt|alloc_fmt|append_fmt_block|alloc_fmt_block)\([^)]{0,1600}?,[[:space:]]*\.\{[[:space:]]*[^.[:space:]}]' \
    "$ROOT_DIR/src" --glob '*.zig' || true)
if [[ -n "$positional_format_args" ]]; then
    printf 'positional generated-text format arguments remain; use named fields:\n%s\n' "$positional_format_args" >&2
    exit 1
fi

unformatted_single_line_calls=$(awk '
$0 ~ /append_fmt\(.*"[^"]*"[^;]*\.\{[[:space:]]*\}[[:space:]]*\)/ {
    printf "%s:%d:%s\n", FILENAME, FNR, $0
}
' $(rg -l 'append_fmt\(' "$ROOT_DIR/src" --glob '*.zig' || true))
if [[ -n "$unformatted_single_line_calls" ]]; then
    printf 'single-line generated text without placeholders must use appendSlice:\n%s\n' "$unformatted_single_line_calls" >&2
    exit 1
fi

# Full generated WAT templates must pass through the shared block normalizer.
# These names are the current static output-template inventory; embedded user
# source and protocol payloads are intentionally outside this gate.
for forbidden in \
    'allocator.dupe(u8, resource_async_core_wat)' \
    'allocator.dupe(u8, resource_async_cancel_core_wat)' \
    'allocator.dupe(u8, generic_record_stream_core_wat)' \
    'allocator.dupe(u8, generic_async_runtime_component_wat)' \
    'allocator.dupe(u8, core_wat)' \
    'allocator.dupe(u8, two_await_core_wat)' \
    'allocator.dupe(u8, cli_result_core_wat)' \
    'allocator.dupe(u8, scalar_result_core_wat)'; do
    if rg -n -F "$forbidden" "$ROOT_DIR/src/build" --glob '*.zig' >/dev/null; then
        printf 'static generated WAT template must use alloc_block: %s\n' "$forbidden" >&2
        exit 1
    fi
done

for forbidden in \
    'allocator.dupe(u8, http_payload_cancel_core_wat)' \
    'allocator.dupe(u8, http_response_body_core_wat)' \
    'allocator.dupe(u8, http_response_body_read_core_wat)' \
    'allocator.dupe(u8, http_request_empty_core_wat)' \
    'allocator.dupe(u8, http_service_core_wat)' \
    'allocator.dupe(u8, http_response_trailers_read_functions)' \
    'allocator.dupe(u8, http_request_body_producer_imports)' \
    'allocator.dupe(u8, http_request_body_producer_helpers_wat)' \
    'allocator.dupe(u8, http_request_send_imports)' \
    'allocator.dupe(u8, http_request_constructor_helper_wat)' \
    'allocator.dupe(u8, http_request_body_constructor_helper_wat)'; do
    if rg -n -F "$forbidden" "$ROOT_DIR/src/build" --glob '*.zig' >/dev/null; then
        printf 'static HTTP generated text must use alloc_block: %s\n' "$forbidden" >&2
        exit 1
    fi
done

for forbidden in \
    'output.appendSlice(allocator, canonical_core_wat[0..close])' \
    'output.appendSlice(allocator, canonical_core_wat[close..])'; do
    if rg -n -F "$forbidden" "$ROOT_DIR/src/build" --glob '*.zig' >/dev/null; then
        printf 'embedded generated WAT must be normalized through alloc_block: %s\n' "$forbidden" >&2
        exit 1
    fi
done

for generated_file in \
    "$ROOT_DIR/src/build/codegen_p3_wait_for.zig" \
    "$ROOT_DIR/src/build/codegen_component_wasi_http.zig"; do
    if rg -n -F 'std.fmt.allocPrint' "$generated_file" >/dev/null; then
        printf 'generated-text module must use codegen_text formatting helpers: %s\n' "$generated_file" >&2
        exit 1
    fi
done

if rg -n -F 'appendSlice(allocator, generic_async_component_wat)' "$ROOT_DIR/src/build" --glob '*.zig' >/dev/null; then
    printf 'static generated WAT template must use append_block: generic_async_component_wat\n' >&2
    exit 1
fi

# The WIT-to-Do emitter writes a two-line generated header. Keep it on the
# shared block path so multi-line generated source does not bypass indentation
# normalization by embedding both lines in appendSlice.
if rg -n -F 'appendSlice(allocator, "// generated by do wit; source WIT is authoritative\n\n")' \
    "$ROOT_DIR/src/wit/emit_do.zig" >/dev/null; then
    printf 'generated Do header must use append_block: emit_do.render_module\n' >&2
    exit 1
fi

# No production generated-text append may hide multiple output lines inside a
# quoted appendSlice literal. Character escaping and test fixture construction
# use different paths and are intentionally outside this check.
multi_line_append_slices=$(rg -n -U -P \
    'appendSlice\([^;]{0,1800}?"[^"\n]*(?:\\n){2}' \
    "$ROOT_DIR/src/build" "$ROOT_DIR/src/wit" --glob '*.zig' || true)
if [[ -n "$multi_line_append_slices" ]]; then
    printf 'multi-line generated text must use a block helper:\n%s\n' "$multi_line_append_slices" >&2
    exit 1
fi

single_line_raw_fmt=$(rg -n -U -P \
    '(?s)(?:generated_text\.)?append_fmt\([^)]{0,1200}?^\s*\\\\' \
    "$ROOT_DIR/src" --glob '*.zig' || true)
if [[ -n "$single_line_raw_fmt" ]]; then
    printf 'single-line raw templates must use append_fmt with a named format:\n%s\n' "$single_line_raw_fmt" >&2
    exit 1
fi

# Generated WAT templates must use named arguments.  A single instruction is
# kept as a normal one-line format string; a multiline block goes through the
# shared block helper instead of a positional raw template.
gc_sync_file="$ROOT_DIR/src/build/codegen_gc_sync.zig"
if rg -n -F 'fn append(self: *BodyEmitter' "$gc_sync_file" >/dev/null ||
   rg -n -F 'self.append(' "$gc_sync_file" >/dev/null; then
    printf 'BodyEmitter generated text must distinguish append_static from append_fmt: %s\n' "$gc_sync_file" >&2
    exit 1
fi
for forbidden in \
    'local.get ${s}' \
    'local.set ${s}' \
    'br ${s}' \
    'i32.const {d}' \
    '.{ receiver_name, field_name }' \
    '.{ index_local, break_label, body_label }'; do
    if rg -n -F "$forbidden" "$gc_sync_file" >/dev/null; then
        printf 'forbidden positional/single-line template remains in %s: %s\n' "$gc_sync_file" "$forbidden" >&2
        exit 1
    fi
done

unindexed_block_calls=$(rg -n -U -P \
    'generated_text\.(?:append_fmt_block|alloc_fmt_block)\((?:(?!\);)[\s\S])*\{[sd]\}' \
    "$ROOT_DIR/src/build" --glob '*.zig' || true)
if [[ -n "$unindexed_block_calls" ]]; then
    printf 'unindexed generated-text block placeholders remain:\n%s\n' "$unindexed_block_calls" >&2
    exit 1
fi

single_line_blocks=$(awk '
function reset() {
    in_call = 0
    raw_lines = 0
    nonblank_lines = 0
}
FNR == 1 { reset() }
/append_fmt_block[[:space:]]*\(/ && !in_call {
    in_call = 1
    raw_lines = 0
    nonblank_lines = 0
}
in_call {
    if ($0 ~ /^[[:space:]]*\\\\/) {
        raw_lines++
        line = $0
        sub(/^[[:space:]]*\\\\/, "", line)
        if (line !~ /^[[:space:]]*$/) nonblank_lines++
    }
    if ($0 !~ /^[[:space:]]*\\\\/ && ($0 ~ /\}\),?[[:space:]]*;?[[:space:]]*$/ || $0 ~ /\),?[[:space:]]*;?[[:space:]]*$/)) {
        if (raw_lines > 0 && nonblank_lines <= 1) {
            printf "%s:%d\n", FILENAME, FNR
        }
        reset()
    }
}
' $(rg -l 'append_fmt_block' "$ROOT_DIR/src" --glob '*.zig' || true))
if [[ -n "$single_line_blocks" ]]; then
    printf 'single-line formatted blocks must use append_fmt:\n%s\n' "$single_line_blocks" >&2
    exit 1
fi

single_line_alloc_blocks=$(awk '
function reset() {
    in_call = 0
    raw_lines = 0
    nonblank_lines = 0
}
FNR == 1 { reset() }
/alloc_fmt_block[[:space:]]*\(/ && !in_call {
    in_call = 1
    raw_lines = 0
    nonblank_lines = 0
}
in_call {
    if ($0 ~ /^[[:space:]]*\\\\/) {
        raw_lines++
        line = $0
        sub(/^[[:space:]]*\\\\/, "", line)
        if (line !~ /^[[:space:]]*$/) nonblank_lines++
    }
    if ($0 !~ /^[[:space:]]*\\\\/ && ($0 ~ /\}\),?[[:space:]]*;?[[:space:]]*$/ || $0 ~ /\),?[[:space:]]*;?[[:space:]]*$/)) {
        if (raw_lines > 0 && nonblank_lines <= 1) {
            printf "%s:%d\n", FILENAME, FNR
        }
        reset()
    }
}
' $(rg -l 'alloc_fmt_block' "$ROOT_DIR/src" --glob '*.zig' || true))
if [[ -n "$single_line_alloc_blocks" ]]; then
    printf 'single-line allocated formatted blocks must use alloc_fmt:\n%s\n' "$single_line_alloc_blocks" >&2
    exit 1
fi

single_line_static_blocks=$(awk '
function reset() {
    in_call = 0
    raw_lines = 0
    nonblank_lines = 0
}
FNR == 1 { reset() }
($0 ~ /append_block[[:space:]]*\(/ || $0 ~ /alloc_block[[:space:]]*\(/) &&
    $0 !~ /append_fmt_block/ && $0 !~ /alloc_fmt_block/ && !in_call {
    in_call = 1
    raw_lines = 0
    nonblank_lines = 0
}
in_call {
    if ($0 ~ /^[[:space:]]*\\\\/) {
        raw_lines++
        line = $0
        sub(/^[[:space:]]*\\\\/, "", line)
        if (line !~ /^[[:space:]]*$/) nonblank_lines++
    }
    if ($0 !~ /^[[:space:]]*\\\\/ && $0 ~ /\),?[[:space:]]*;?[[:space:]]*$/) {
        if (raw_lines == 1) {
            printf "%s:%d\n", FILENAME, FNR
        }
        reset()
    }
}
' $(rg -l 'append_block' "$ROOT_DIR/src" --glob '*.zig' || true))
if [[ -n "$single_line_static_blocks" ]]; then
    printf 'single-line static blocks must use appendSlice or allocator.dupe:\n%s\n' "$single_line_static_blocks" >&2
    exit 1
fi

printf 'generated-text block API audit: ok\n'
