//! Semantic analysis — public entry and orchestration.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const sema_util = @import("sema_util.zig");
const sema_func = @import("sema_func.zig");
const sema_struct = @import("sema_struct.zig");
const sema_import = @import("sema_import.zig");
const sema_type = @import("sema_type.zig");
const sema_ctrl = @import("sema_ctrl.zig");

pub const ErrorSite = sema_error.ErrorSite;

pub fn takeLastErrorSite() ?ErrorSite {
    return sema_error.takeLastErrorSite();
}

pub fn checkProgram(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !void {
    sema_error.clearLastErrorSite();
    if (program.source_len == 0) return error.EmptySource;
    if (program.token_count == 0) return error.EmptyTokenStream;
    try sema_func.checkPrivateLValueAssign(tokens);
    try sema_func.checkFuncDeclNaming(tokens);
    try sema_func.checkFuncReturnArrowSyntax(tokens);
    try sema_func.checkStartDeclSyntax(tokens);
    try sema_func.checkFuncParamNames(allocator, tokens);
    try sema_func.checkInlineFuncParamTypes(tokens);
    try sema_func.checkSynthErrorFuncParamTypes(tokens);
    try sema_func.checkFuncParamTypeRestrictions(tokens);
    try sema_func.checkFuncSignatureConflicts(allocator, tokens);
    try sema_struct.checkPathAccess(tokens);
    try sema_struct.checkFieldSegmentPositions(tokens);
    try sema_import.checkHostImports(allocator, tokens);
    try sema_import.checkLocalImports(tokens);
    if (program.top_level_count == 0) return sema_util.markErrorAt(tokens, 0, error.NoTopLevelDecl);

    try sema_type.checkTypeDeclNaming(tokens);
    try sema_type.checkTypeDeclNameConflicts(allocator, tokens);
    try sema_type.checkErrorDeclBranches(tokens);
    try sema_type.checkTopValueDeclNames(tokens);
    try sema_struct.checkStructFieldNames(allocator, tokens);
    try sema_type.checkTypeRefs(tokens);
    try sema_type.checkParenthesizedTypeArgs(tokens);
    try sema_type.checkParenthesizedTypes(tokens);
    try sema_type.checkGenericTypeArgArity(tokens);
    try sema_struct.checkGenericStructCtorTypeArgs(tokens);
    try sema_struct.checkTupleCtorArity(tokens);
    try sema_struct.checkTupleGetIndex(tokens);
    try sema_type.checkForbiddenSourceTypeNames(tokens);
    try sema_type.checkBareNilTypes(tokens);
    try sema_type.checkInlineFuncTypeUnionBranches(tokens);
    try sema_type.checkDuplicateUnionBranches(tokens);
    try sema_struct.checkStructCtorFields(allocator, tokens);
    try sema_struct.checkPathIndexSegments(tokens);
    try sema_struct.checkDirectPathSource(tokens);
    try sema_ctrl.checkConstraintLayout(tokens);
    try sema_type.checkUnboundTypeParamRefs(tokens);
    try sema_func.checkSpreadCallTargets(allocator, tokens);
    try sema_func.checkGenericCallInference(allocator, program, tokens);
    try sema_type.checkSynthErrorTypePositions(tokens);
    try sema_func.checkLineStringRootPositions(program, tokens);
    try sema_type.checkUpperValueExprs(program, tokens);
    try sema_func.checkSingleValuePositions(allocator, program, tokens);
    try sema_func.checkKnownConditionBoolSites(allocator, program, tokens);
    try sema_func.checkLambdaUsage(allocator, program, tokens);
    try sema_func.checkLambdaOverloadCalls(allocator, program, tokens);
    try sema_func.checkIsTypeArgs(tokens);
    try sema_func.checkAsTypeArgs(tokens);
    try sema_ctrl.checkLoopHeader(tokens);
    try sema_ctrl.checkFieldReflection(allocator, tokens);
    try sema_ctrl.checkLoopLabels(allocator, tokens);
    try sema_ctrl.checkDeferStmts(allocator, tokens);
    try sema_ctrl.checkAssignmentConstraints(allocator, tokens);
}
