//! Semantic analysis — public entry and orchestration.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_function_signatures = @import("sema_function_signatures.zig");
const sema_function_calls = @import("sema_function_calls.zig");
const sema_function_lambdas = @import("sema_function_lambdas.zig");
const sema_structures = @import("sema_structures.zig");
const sema_imports = @import("sema_imports.zig");
const sema_type_checks = @import("sema_type_checks.zig");
const sema_control_flow = @import("sema_control_flow.zig");
const sema_field_checks = @import("sema_field_checks.zig");
const sema_constraints = @import("sema_constraints.zig");

pub const ErrorSite = sema_error.ErrorSite;

pub fn take_last_error_site() ?ErrorSite {
    return sema_error.take_last_error_site();
}

pub fn check_program(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !void {
    sema_error.clear_last_error_site();
    if (program.source_len == 0) return error.EmptySource;
    if (program.token_count == 0) return error.EmptyTokenStream;
    try sema_function_signatures.check_private_l_value_assign(tokens);
    try sema_function_signatures.check_func_decl_naming(tokens);
    try sema_function_signatures.check_func_return_arrow_syntax(tokens);
    try sema_function_signatures.check_start_decl_syntax(tokens);
    try sema_function_signatures.check_func_param_names(allocator, tokens);
    try sema_function_signatures.check_inline_func_param_types(tokens);
    try sema_function_signatures.check_synth_error_func_param_types(tokens);
    try sema_function_signatures.check_func_param_type_restrictions(tokens);
    try sema_function_signatures.check_func_signature_conflicts(allocator, tokens);
    try sema_structures.check_path_access(tokens);
    try sema_structures.check_field_segment_positions(tokens);
    try sema_imports.check_host_imports(allocator, tokens);
    try sema_imports.check_local_imports(tokens);
    if (program.top_level_count == 0) return sema_tokens.mark_error_at(tokens, 0, error.NoTopLevelDecl);

    try sema_type_checks.check_type_decl_naming(tokens);
    try sema_type_checks.check_type_decl_name_conflicts(allocator, tokens);
    try sema_type_checks.check_error_decl_branches(tokens);
    try sema_type_checks.check_top_value_decl_names(tokens);
    try sema_structures.check_struct_field_names(allocator, tokens);
    try sema_type_checks.check_type_refs(tokens);
    try sema_type_checks.check_parenthesized_type_args(tokens);
    try sema_type_checks.check_parenthesized_types(tokens);
    try sema_type_checks.check_generic_type_arg_arity(tokens);
    try sema_structures.check_generic_struct_ctor_type_args(tokens);
    try sema_structures.check_tuple_ctor_arity(tokens);
    try sema_structures.check_tuple_get_index(tokens);
    try sema_type_checks.check_forbidden_source_type_names(tokens);
    try sema_type_checks.check_bare_nil_types(tokens);
    try sema_type_checks.check_inline_func_type_union_branches(tokens);
    try sema_type_checks.check_duplicate_union_branches(tokens);
    try sema_structures.check_struct_ctor_fields(allocator, tokens);
    try sema_structures.check_path_index_segments(tokens);
    try sema_structures.check_direct_path_source(tokens);
    try sema_constraints.check_constraint_layout(tokens);
    try sema_type_checks.check_unbound_type_param_refs(tokens);
    try sema_function_calls.check_spread_call_targets(allocator, tokens);
    try sema_function_calls.check_generic_call_inference(allocator, program, tokens);
    try sema_type_checks.check_synth_error_type_positions(tokens);
    try sema_function_calls.check_line_string_root_positions(program, tokens);
    try sema_type_checks.check_upper_value_exprs(program, tokens);
    try sema_function_calls.check_single_value_positions(allocator, program, tokens);
    try sema_function_calls.check_known_condition_bool_sites(allocator, program, tokens);
    try sema_function_lambdas.check_lambda_usage(allocator, program, tokens);
    try sema_function_lambdas.check_lambda_overload_calls(allocator, program, tokens);
    try sema_function_calls.check_is_type_args(tokens);
    try sema_function_calls.check_as_type_args(tokens);
    try sema_control_flow.check_loop_header(tokens);
    try sema_field_checks.check_field_reflection(allocator, tokens);
    try sema_control_flow.check_loop_labels(allocator, tokens);
    try sema_control_flow.check_defer_stmts(allocator, tokens);
    try sema_constraints.check_assignment_constraints(allocator, tokens);
}
