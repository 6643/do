//! Storage type and layout query facade with no WAT emission.
//!
//! Keep callers that only need storage shape information decoupled from the
//! storage operation/value emit import boundary.

const values = @import("codegen_emit_storage_values.zig");

pub const ParsedStorageType = values.ParsedStorageType;
pub const ManagedPayloadBinding = values.ManagedPayloadBinding;
pub const storageBindingElemType = values.storageBindingElemType;
pub const managedPayloadBinding = values.managedPayloadBinding;
pub const parseStorageType = values.parseStorageType;
pub const storageElementByteWidthForType = values.storageElementByteWidthForType;
pub const storagePackLayoutForElem = values.storagePackLayoutForElem;
pub const tupleFieldPathType = values.tupleFieldPathType;
pub const substituteStructFieldType = values.substituteStructFieldType;
pub const findLocalFieldType = values.findLocalFieldType;
pub const inferExprType = values.inferExprType;
pub const inferStorageContentComparisonType = values.inferStorageContentComparisonType;
pub const storageContentArgCompatible = values.storageContentArgCompatible;
pub const isManagedPayloadComparableType = values.isManagedPayloadComparableType;
pub const findStructFieldType = values.findStructFieldType;
pub const inferSetCallType = values.inferSetCallType;
pub const inferPutCallType = values.inferPutCallType;
pub const inferFieldGetCallType = values.inferFieldGetCallType;
pub const inferFieldSetCallType = values.inferFieldSetCallType;
pub const inferGetCallType = values.inferGetCallType;
pub const inferTupleFieldPathGetType = values.inferTupleFieldPathGetType;
pub const findStructField = values.findStructField;
pub const unionLocalDefaultPayloadType = values.unionLocalDefaultPayloadType;
pub const findNarrowedUnionType = values.findNarrowedUnionType;
pub const lambdaParamTypeName = values.lambdaParamTypeName;
pub const lambdaExplicitReturnType = values.lambdaExplicitReturnType;
pub const inferLambdaExprReturnType = values.inferLambdaExprReturnType;
pub const managedPayloadElemTypeFromName = values.managedPayloadElemTypeFromName;
