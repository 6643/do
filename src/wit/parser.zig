const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("model.zig");

pub const ParseError = error{
    DuplicateInterface,
    DuplicateWorld,
    InvalidDeclaration,
    InvalidVersion,
    MissingPackage,
    UnexpectedToken,
    UnsupportedTypeArity,
};

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const lexer.Token,
    index: usize,

    fn peek(self: *const Parser) ?lexer.Token {
        if (self.index >= self.tokens.len) return null;
        return self.tokens[self.index];
    }

    fn at(self: *const Parser, lexeme: []const u8) bool {
        const token = self.peek() orelse return false;
        return std.mem.eql(u8, token.lexeme, lexeme);
    }

    fn take(self: *Parser) ?lexer.Token {
        const token = self.peek() orelse return null;
        self.index += 1;
        return token;
    }

    fn take_if(self: *Parser, lexeme: []const u8) bool {
        if (!self.at(lexeme)) return false;
        _ = self.take();
        return true;
    }

    fn expect(self: *Parser, lexeme: []const u8) ParseError!lexer.Token {
        const token = self.take() orelse return error.UnexpectedToken;
        if (!std.mem.eql(u8, token.lexeme, lexeme)) return error.UnexpectedToken;
        return token;
    }

    fn expect_ident(self: *Parser) ParseError!lexer.Token {
        const token = self.take() orelse return error.UnexpectedToken;
        if (token.kind != .ident) return error.UnexpectedToken;
        return token;
    }

    fn span(self: *const Parser, start: lexer.Token, end: lexer.Token) model.Span {
        _ = self;
        return .{
            .start = start.span_start,
            .end = end.span_end,
            .line = start.line,
            .column = start.column,
        };
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) (ParseError || lexer.LexerError || std.mem.Allocator.Error)!model.Ast {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const parsed = try parse_in_arena(arena.allocator(), source);
    return .{
        .arena = arena,
        .source = parsed.source,
        .package = parsed.package,
        .interfaces = parsed.interfaces,
        .worlds = parsed.worlds,
    };
}

pub fn parse_in_arena(
    allocator: std.mem.Allocator,
    source: []const u8,
) (ParseError || lexer.LexerError || std.mem.Allocator.Error)!model.Parsed {
    const tokens = try lexer.tokenize(allocator, source);
    var parser = Parser{
        .allocator = allocator,
        .source = source,
        .tokens = tokens,
        .index = 0,
    };

    var package: ?model.PackageDecl = null;
    var interfaces = std.ArrayList(model.InterfaceDecl).empty;
    var worlds = std.ArrayList(model.WorldDecl).empty;

    while (parser.peek() != null) {
        if (parser.at("@")) {
            try skip_annotation(&parser);
        } else if (parser.at("package")) {
            if (package != null) return error.InvalidDeclaration;
            package = try parse_package(&parser);
        } else if (parser.at("interface")) {
            const interface = try parse_interface(&parser);
            for (interfaces.items) |existing| {
                if (std.mem.eql(u8, existing.name, interface.name)) return error.DuplicateInterface;
            }
            try interfaces.append(allocator, interface);
        } else if (parser.at("world")) {
            const world = try parse_world(&parser);
            for (worlds.items) |existing| {
                if (std.mem.eql(u8, existing.name, world.name)) return error.DuplicateWorld;
            }
            try worlds.append(allocator, world);
        } else if (parser.at("use") or parser.at("include")) {
            _ = try parse_raw_decl(&parser);
        } else {
            return error.InvalidDeclaration;
        }
    }

    return .{
        .source = source,
        .package = package orelse return error.MissingPackage,
        .interfaces = try interfaces.toOwnedSlice(allocator),
        .worlds = try worlds.toOwnedSlice(allocator),
    };
}

fn parse_package(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.PackageDecl {
    const start = try parser.expect("package");
    const namespace = try parser.expect_ident();
    _ = try parser.expect(":");
    const name = try parser.expect_ident();
    _ = try parser.expect("@");
    const version_token = parser.take() orelse return error.InvalidVersion;
    if (version_token.kind != .number) return error.InvalidVersion;
    const version = parse_version(version_token.lexeme) orelse return error.InvalidVersion;
    const end = try parser.expect(";");
    return .{
        .namespace = namespace.lexeme,
        .name = name.lexeme,
        .version = version,
        .span = parser.span(start, end),
    };
}

fn parse_version(raw: []const u8) ?model.Version {
    const prerelease_start = std.mem.indexOfScalar(u8, raw, '-') orelse raw.len;
    const numeric = raw[0..prerelease_start];
    const prerelease = if (prerelease_start < raw.len) raw[prerelease_start + 1 ..] else "";
    if (prerelease_start < raw.len and prerelease.len == 0) return null;
    var parts = std.mem.splitScalar(u8, numeric, '.');
    const major = parse_version_part(parts.next() orelse return null) orelse return null;
    const minor = parse_version_part(parts.next() orelse return null) orelse return null;
    const patch = parse_version_part(parts.next() orelse return null) orelse return null;
    if (parts.next() != null) return null;
    return .{ .major = major, .minor = minor, .patch = patch, .prerelease = prerelease };
}

fn parse_version_part(raw: []const u8) ?u32 {
    if (raw.len == 0) return null;
    return std.fmt.parseInt(u32, raw, 10) catch null;
}

fn parse_interface(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.InterfaceDecl {
    const start = try parser.expect("interface");
    const name = try parser.expect_ident();
    _ = try parser.expect("{");

    var uses = std.ArrayList(model.UseDecl).empty;
    var includes = std.ArrayList(model.IncludeDecl).empty;
    var aliases = std.ArrayList(model.TypeAlias).empty;
    var records = std.ArrayList(model.RecordDecl).empty;
    var variants = std.ArrayList(model.VariantDecl).empty;
    var enums = std.ArrayList(model.EnumDecl).empty;
    var flags = std.ArrayList(model.FlagsDecl).empty;
    var resources = std.ArrayList(model.ResourceDecl).empty;
    var functions = std.ArrayList(model.FunctionDecl).empty;

    while (!parser.at("}")) {
        if (parser.peek() == null) return error.UnexpectedToken;
        if (parser.at("@")) {
            try skip_annotation(parser);
        } else if (parser.at("use")) {
            try uses.append(parser.allocator, try parse_use(parser));
        } else if (parser.at("include")) {
            try includes.append(parser.allocator, try parse_include(parser));
        } else if (parser.at("type")) {
            try aliases.append(parser.allocator, try parse_alias(parser));
        } else if (parser.at("record")) {
            try records.append(parser.allocator, try parse_record(parser));
        } else if (parser.at("variant")) {
            try variants.append(parser.allocator, try parse_variant(parser));
        } else if (parser.at("enum")) {
            try enums.append(parser.allocator, try parse_enum(parser));
        } else if (parser.at("flags")) {
            try flags.append(parser.allocator, try parse_flags(parser));
        } else if (parser.at("resource")) {
            try resources.append(parser.allocator, try parse_resource(parser));
        } else {
            try functions.append(parser.allocator, try parse_function(parser));
        }
    }
    const end = try parser.expect("}");

    return .{
        .name = name.lexeme,
        .uses = try uses.toOwnedSlice(parser.allocator),
        .includes = try includes.toOwnedSlice(parser.allocator),
        .aliases = try aliases.toOwnedSlice(parser.allocator),
        .records = try records.toOwnedSlice(parser.allocator),
        .variants = try variants.toOwnedSlice(parser.allocator),
        .enums = try enums.toOwnedSlice(parser.allocator),
        .flags = try flags.toOwnedSlice(parser.allocator),
        .resources = try resources.toOwnedSlice(parser.allocator),
        .functions = try functions.toOwnedSlice(parser.allocator),
        .span = parser.span(start, end),
    };
}

fn parse_world(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.WorldDecl {
    const start = try parser.expect("world");
    const name = try parser.expect_ident();
    _ = try parser.expect("{");
    var imports = std.ArrayList(model.WorldImport).empty;
    var exports = std.ArrayList(model.WorldImport).empty;
    while (!parser.at("}")) {
        const kind = parser.take() orelse return error.UnexpectedToken;
        if (std.mem.eql(u8, kind.lexeme, "@")) {
            parser.index -= 1;
            try skip_annotation(parser);
            continue;
        }
        if (!std.mem.eql(u8, kind.lexeme, "import") and !std.mem.eql(u8, kind.lexeme, "export")) {
            return error.UnexpectedToken;
        }
        const target_start = parser.peek() orelse return error.UnexpectedToken;
        const end = try consume_raw_until_semicolon(parser);
        const target = parser.source[target_start.span_start..end.span_start];
        const import_name = world_import_name(target) orelse return error.UnexpectedToken;
        const item = model.WorldImport{ .name = import_name, .target = target, .span = parser.span(kind, end) };
        if (std.mem.eql(u8, kind.lexeme, "import")) {
            try imports.append(parser.allocator, item);
        } else {
            try exports.append(parser.allocator, item);
        }
    }
    const end = try parser.expect("}");
    return .{
        .name = name.lexeme,
        .imports = try imports.toOwnedSlice(parser.allocator),
        .exports = try exports.toOwnedSlice(parser.allocator),
        .span = parser.span(start, end),
    };
}

fn world_import_name(raw: []const u8) ?[]const u8 {
    var target = std.mem.trim(u8, raw, " \t\r\n");
    if (target.len == 0) return null;
    if (std.mem.indexOfScalar(u8, target, '{')) |index| target = target[0..index];
    if (std.mem.lastIndexOfScalar(u8, target, '/')) |index| target = target[index + 1 ..];
    if (std.mem.indexOfScalar(u8, target, '@')) |index| target = target[0..index];
    return if (target.len == 0) null else std.mem.trim(u8, target, " \t\r\n");
}

fn parse_use(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.UseDecl {
    const start = try parser.expect("use");
    const target_start = parser.peek() orelse return error.UnexpectedToken;
    const end = try consume_raw_until_semicolon(parser);
    return .{ .target = parser.source[target_start.span_start..end.span_start], .span = parser.span(start, end) };
}

fn parse_include(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.IncludeDecl {
    const start = try parser.expect("include");
    const target_start = parser.peek() orelse return error.UnexpectedToken;
    const end = try consume_raw_until_semicolon(parser);
    return .{ .target = parser.source[target_start.span_start..end.span_start], .span = parser.span(start, end) };
}

fn parse_raw_decl(parser: *Parser) (ParseError || std.mem.Allocator.Error)!void {
    _ = parser.take();
    _ = try consume_raw_until_semicolon(parser);
}

fn consume_raw_until_semicolon(parser: *Parser) ParseError!lexer.Token {
    while (parser.peek()) |token| {
        if (std.mem.eql(u8, token.lexeme, ";")) {
            _ = parser.take();
            return token;
        }
        _ = parser.take();
    }
    return error.UnexpectedToken;
}

fn skip_annotation(parser: *Parser) ParseError!void {
    _ = try parser.expect("@");
    _ = try parser.expect_ident();
    if (parser.take_if("(")) {
        try skip_balanced(parser, "(");
    } else if (parser.take_if("=")) {
        _ = parser.take() orelse return error.UnexpectedToken;
    }
}

fn parse_resource(parser: *Parser) ParseError!model.ResourceDecl {
    const start = try parser.expect("resource");
    const name = try parser.expect_ident();
    if (parser.take_if("{")) {
        skip_balanced(parser, "{") catch return error.UnexpectedToken;
    } else if (!parser.take_if(";")) {
        return error.UnexpectedToken;
    }
    const end = parser.tokens[parser.index - 1];
    return .{ .name = name.lexeme, .has_drop = true, .span = parser.span(start, end) };
}

fn skip_balanced(parser: *Parser, opening: []const u8) ParseError!void {
    const closing = if (std.mem.eql(u8, opening, "{")) "}" else if (std.mem.eql(u8, opening, "(")) ")" else if (std.mem.eql(u8, opening, "[")) "]" else return error.UnexpectedToken;
    var depth: usize = 1;
    while (parser.peek()) |token| {
        _ = parser.take();
        if (std.mem.eql(u8, token.lexeme, opening)) depth += 1;
        if (std.mem.eql(u8, token.lexeme, closing)) {
            depth -= 1;
            if (depth == 0) return;
        }
    }
    return error.UnexpectedToken;
}

fn parse_alias(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.TypeAlias {
    const start = try parser.expect("type");
    const name = try parser.expect_ident();
    _ = try parser.expect("=");
    const type_ref = try parse_type(parser);
    const end = try parser.expect(";");
    return .{ .name = name.lexeme, .type_ref = type_ref, .span = parser.span(start, end) };
}

fn parse_record(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.RecordDecl {
    const start = try parser.expect("record");
    const name = try parser.expect_ident();
    _ = try parser.expect("{");
    var fields = std.ArrayList(model.Field).empty;
    while (!parser.at("}")) {
        const field_name = try parser.expect_ident();
        _ = try parser.expect(":");
        const type_ref = try parse_type(parser);
        const separator = parser.take() orelse return error.UnexpectedToken;
        if (!std.mem.eql(u8, separator.lexeme, ",") and !std.mem.eql(u8, separator.lexeme, ";")) return error.UnexpectedToken;
        try fields.append(parser.allocator, .{ .name = field_name.lexeme, .type_ref = type_ref, .span = parser.span(field_name, separator) });
    }
    const end = try parser.expect("}");
    return .{ .name = name.lexeme, .fields = try fields.toOwnedSlice(parser.allocator), .span = parser.span(start, end) };
}

fn parse_variant(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.VariantDecl {
    const start = try parser.expect("variant");
    const name = try parser.expect_ident();
    _ = try parser.expect("{");
    const cases = try parse_cases(parser, true);
    const end = parser.tokens[parser.index - 1];
    return .{ .name = name.lexeme, .cases = cases, .span = parser.span(start, end) };
}

fn parse_enum(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.EnumDecl {
    const start = try parser.expect("enum");
    const name = try parser.expect_ident();
    _ = try parser.expect("{");
    const cases = try parse_cases(parser, false);
    const end = parser.tokens[parser.index - 1];
    return .{ .name = name.lexeme, .cases = cases, .span = parser.span(start, end) };
}

fn parse_cases(parser: *Parser, allow_payload: bool) (ParseError || std.mem.Allocator.Error)![]const model.Case {
    var cases = std.ArrayList(model.Case).empty;
    while (!parser.at("}")) {
        const name = try parser.expect_ident();
        var payload: ?*model.TypeRef = null;
        if (allow_payload and parser.take_if("(")) {
            payload = try parse_type(parser);
            _ = try parser.expect(")");
        }
        const separator = parser.take() orelse return error.UnexpectedToken;
        if (!std.mem.eql(u8, separator.lexeme, ",") and !std.mem.eql(u8, separator.lexeme, "}")) return error.UnexpectedToken;
        try cases.append(parser.allocator, .{ .name = name.lexeme, .payload = payload, .span = parser.span(name, separator) });
        if (std.mem.eql(u8, separator.lexeme, "}")) break;
    }
    if (parser.index == 0 or !std.mem.eql(u8, parser.tokens[parser.index - 1].lexeme, "}")) {
        _ = try parser.expect("}");
    }
    return cases.toOwnedSlice(parser.allocator);
}

fn parse_flags(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.FlagsDecl {
    const start = try parser.expect("flags");
    const name = try parser.expect_ident();
    _ = try parser.expect("{");
    var values = std.ArrayList([]const u8).empty;
    while (!parser.at("}")) {
        const value = try parser.expect_ident();
        try values.append(parser.allocator, value.lexeme);
        const separator = parser.take() orelse return error.UnexpectedToken;
        if (std.mem.eql(u8, separator.lexeme, "}")) break;
        if (!std.mem.eql(u8, separator.lexeme, ",")) return error.UnexpectedToken;
    }
    _ = try parser.expect("}");
    const end = if (parser.index > 0) parser.tokens[parser.index - 1] else return error.UnexpectedToken;
    return .{ .name = name.lexeme, .flags = try values.toOwnedSlice(parser.allocator), .span = parser.span(start, end) };
}

fn parse_function(parser: *Parser) (ParseError || std.mem.Allocator.Error)!model.FunctionDecl {
    const name = try parser.expect_ident();
    const start = name;
    _ = try parser.expect(":");
    const is_async = parser.take_if("async");
    _ = try parser.expect("func");
    _ = try parser.expect("(");
    var params = std.ArrayList(model.Param).empty;
    while (!parser.at(")")) {
        const param_name = try parser.expect_ident();
        _ = try parser.expect(":");
        const type_ref = try parse_type(parser);
        try params.append(parser.allocator, .{ .name = param_name.lexeme, .type_ref = type_ref, .span = type_ref.span });
        if (!parser.take_if(",")) break;
    }
    _ = try parser.expect(")");
    var result: ?*model.TypeRef = null;
    if (parser.take_if("->")) result = try parse_type(parser);
    const end = try parser.expect(";");
    const result_type = result;
    return .{
        .name = name.lexeme,
        .is_async = is_async,
        .params = try params.toOwnedSlice(parser.allocator),
        .result = result_type,
        .effects = .{
            .is_async = is_async,
            .has_future = if (result_type) |type_ref| model.type_has_kind(type_ref, .future) else false,
            .has_stream = if (result_type) |type_ref| model.type_has_kind(type_ref, .stream) else false,
            .has_resource = false,
        },
        .span = parser.span(start, end),
    };
}

fn parse_type(parser: *Parser) (ParseError || std.mem.Allocator.Error)!*model.TypeRef {
    const name_token = try parser.expect_ident();
    var last_token = name_token;
    var kind = model.primitive_kind(name_token.lexeme) orelse model.TypeKind.named;
    if (std.mem.eql(u8, name_token.lexeme, "list")) kind = .list;
    if (std.mem.eql(u8, name_token.lexeme, "option")) kind = .option;
    if (std.mem.eql(u8, name_token.lexeme, "result")) kind = .result;
    if (std.mem.eql(u8, name_token.lexeme, "future")) kind = .future;
    if (std.mem.eql(u8, name_token.lexeme, "stream")) kind = .stream;
    if (std.mem.eql(u8, name_token.lexeme, "tuple")) kind = .tuple;
    if (std.mem.eql(u8, name_token.lexeme, "own")) kind = .own;
    if (std.mem.eql(u8, name_token.lexeme, "borrow")) kind = .borrow;

    var args = std.ArrayList(*model.TypeRef).empty;
    if (parser.take_if("<")) {
        if (!parser.at(">")) {
            while (true) {
                try args.append(parser.allocator, try parse_type(parser));
                if (!parser.take_if(",")) break;
            }
        }
        last_token = try parser.expect(">");
    }
    const ownership: model.OwnershipMode = switch (kind) {
        .own => .owned,
        .borrow => .borrowed,
        else => .none,
    };
    const type_ref = parser.allocator.create(model.TypeRef) catch return error.OutOfMemory;
    type_ref.* = .{
        .kind = kind,
        .name = name_token.lexeme,
        .args = try args.toOwnedSlice(parser.allocator),
        .ownership = ownership,
        .span = parser.span(name_token, last_token),
    };
    return type_ref;
}
