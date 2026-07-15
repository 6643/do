//! Struct field access, metadata, and reflection facade.

const structs = @import("codegen_emit_struct.zig");

pub const emitFieldReflectionStaticIf = structs.emitFieldReflectionStaticIf;
pub const collectFieldReflectionStaticIf = structs.collectFieldReflectionStaticIf;
pub const emitFieldReflectionStaticBranch = structs.emitFieldReflectionStaticBranch;
pub const collectFieldReflectionStaticBranch = structs.collectFieldReflectionStaticBranch;
pub const emitFieldReflectionBody = structs.emitFieldReflectionBody;
pub const emitFieldReflectionLoopBlock = structs.emitFieldReflectionLoopBlock;
pub const emitManagedStructFieldSet = structs.emitManagedStructFieldSet;
pub const emitStructFieldValue = structs.emitStructFieldValue;
pub const emitStructFieldMetaSetAssignment = structs.emitStructFieldMetaSetAssignment;
pub const fieldStaticValuesEqual = structs.fieldStaticValuesEqual;
pub const fieldReflectionLocalVisible = structs.fieldReflectionLocalVisible;
pub const fieldReflectionLocalNamePrefix = structs.fieldReflectionLocalNamePrefix;
pub const emitStructFieldLocalGet = structs.emitStructFieldLocalGet;
pub const emitStructFieldLocalSet = structs.emitStructFieldLocalSet;
pub const emitStructFieldsFromLocal = structs.emitStructFieldsFromLocal;
pub const appendManagedStructFieldPtr = structs.appendManagedStructFieldPtr;
pub const fieldReflectionIfParts = structs.fieldReflectionIfParts;
pub const fieldStaticBoolExpr = structs.fieldStaticBoolExpr;
pub const fieldStaticValue = structs.fieldStaticValue;
pub const fieldVisibleFromTokens = structs.fieldVisibleFromTokens;
pub const isPrivateFieldName = structs.isPrivateFieldName;
pub const emitManagedStructExprFieldGet = structs.emitManagedStructExprFieldGet;
pub const emitFieldReflectionIntrinsic = structs.emitFieldReflectionIntrinsic;
pub const emitFieldGetCall = structs.emitFieldGetCall;
pub const emitUnmanagedStructFieldGet = structs.emitUnmanagedStructFieldGet;
pub const borrowedFieldMetaLocalSet = structs.borrowedFieldMetaLocalSet;
pub const singleFieldMetaArg = structs.singleFieldMetaArg;
pub const fieldGetLastUseMoveSource = structs.fieldGetLastUseMoveSource;
pub const collectFieldReflectionBodyLocals = structs.collectFieldReflectionBodyLocals;
pub const fieldReflectionScopedCleanupLocalSet = structs.fieldReflectionScopedCleanupLocalSet;
