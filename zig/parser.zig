const std = @import("std");
const token = @import("token.zig");
const ast = @import("ast.zig");

pub const ParseError = error{
    UnexpectedToken,
    ExpectedToken,
    Todo,
    OutOfMemory,
} || std.fmt.ParseIntError;

pub const Parser = struct {
    tokens: []const token.Token,
    pos: usize = 0,
    tree: ast.Tree,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, source: [:0]const u8, tokens: []const token.Token) Parser {
        const arena = std.heap.ArenaAllocator.init(allocator);
        return .{ .tokens = tokens, .tree = ast.Tree.init(source, tokens), .arena = arena };
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
    }

    pub fn parse(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        var root_nodes = std.ArrayListUnmanaged(ast.NodeIndex){};

        while (self.peek().tag != .eof) {
            while (self.match(.semicolon) or self.match(.comma)) {}
            if (self.peek().tag == .eof) break;
            const node = try self.parseTopLevel();
            try root_nodes.append(allocator, node);
        }

        return self.tree.addNode(allocator, .{
            .tag = .root,
            .main_token = 0,
            .data = .{ .root = .{ .children = try allocator.dupe(ast.NodeIndex, root_nodes.items) } },
        });
    }

    fn parseTopLevel(self: *Parser) ParseError!ast.NodeIndex {
        const tok = self.peek();
        if (tok.tag == .identifier) {
            var i: usize = 1;

            if (self.peekAt(i).tag == .less) {
                i += 1;
                var depth: u32 = 1;
                while (depth > 0) {
                    const t = self.peekAt(i);
                    if (t.tag == .less) depth += 1;
                    if (t.tag == .greater) depth -= 1;
                    if (t.tag == .eof) break;
                    i += 1;
                }
            }

            if (self.peekAt(i).tag == .hash_tag) {
                i += 1;
                i += 1;
                if (self.peekAt(i).tag == .l_brace) {
                    i += 1;
                    var depth: u32 = 1;
                    while (depth > 0) {
                        const t = self.peekAt(i);
                        if (t.tag == .l_brace) depth += 1;
                        if (t.tag == .r_brace) depth -= 1;
                        if (t.tag == .eof) break;
                        i += 1;
                    }
                }
            }

            const next = self.peekAt(i);
            std.debug.print("DEBUG: parseTopLevel sniffing identifier, i: {d}, next: {any}\\n", .{ i, next.tag });

            if (next.tag == .assign) {
                return self.parseEnumAssignDef();
            }

            if (next.tag == .l_brace) {
                if (self.peekAt(i + 1).tag == .dot) {
                    return self.parseEnumDef();
                }
                return self.parseStructDef();
            } else if (next.tag == .l_paren) {
                return self.parseFnDef();
            } else if (next.tag == .less) {
                var j = i + 1;
                var depth: u32 = 1;
                while (depth > 0) {
                    const t = self.peekAt(j);
                    if (t.tag == .less) depth += 1;
                    if (t.tag == .greater) depth -= 1;
                    if (t.tag == .eof) break;
                    j += 1;
                }
                if (self.peekAt(j).tag == .l_brace) {
                    if (self.peekAt(j + 1).tag == .dot) {
                        return self.parseEnumDef();
                    }
                    return self.parseStructDef();
                }
                return self.parseExpression(0);
            }
        } else if (tok.tag == .hash_tag) {
            return self.parseConstraintDef();
        }
        if (self.match(.kw_loop)) {
            return self.parseLoopExpr();
        }
        return self.parseExpression(0);
    }

    fn parseConstraintDef(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        _ = try self.expect(.hash_tag);
        const name_tok = try self.expect(.identifier);
        const name = self.tree.source[name_tok.loc.start..name_tok.loc.end];

        if (self.match(.l_paren)) {
            while (self.peek().tag != .r_paren) _ = self.advance();
            _ = try self.expect(.r_paren);
            if (self.match(.arrow_out)) {
                _ = try self.parseType();
            }
            return self.tree.addNode(allocator, .{
                .tag = .constraint_def,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .constraint_def = .{ .name = name } },
            });
        } else {
            const node = try self.parseConstraintBlock(name);
            return node;
        }
    }

    fn parseStructDef(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const name_tok = try self.expect(.identifier);
        const name = self.tree.source[name_tok.loc.start..name_tok.loc.end];

        const generic_params = try self.parseGenericParams();

        _ = try self.expect(.l_brace);

        var fields = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (!self.match(.r_brace)) {
            const f_name_tok = try self.expect(.identifier);
            const f_name = self.tree.source[f_name_tok.loc.start..f_name_tok.loc.end];
            const f_type_node = try self.parseType();

            if (self.match(.assign)) {
                _ = try self.parseExpression(0);
            }

            const field = try self.tree.addNode(allocator, .{
                .tag = .field_def,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .field_def = .{ .name = f_name, .type_node = f_type_node, .attr = .{ .is_private = f_name[0] == '.' } } },
            });
            try fields.append(allocator, field);
            _ = self.match(.comma);
        }

        return self.tree.addNode(allocator, .{
            .tag = .struct_def,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .struct_def = .{ .name = name, .generic_params = generic_params, .fields = try allocator.dupe(ast.NodeIndex, fields.items) } },
        });
    }

    fn parseEnumDef(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const name_tok = try self.expect(.identifier);
        const name = self.tree.source[name_tok.loc.start..name_tok.loc.end];

        const generic_params = try self.parseGenericParams();

        _ = try self.expect(.l_brace);

        var variants = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (!self.match(.r_brace)) {
            _ = try self.expect(.dot);
            const v_name_tok = try self.expect(.identifier);
            const v_name = self.tree.source[v_name_tok.loc.start..v_name_tok.loc.end];

            var payload_type: ast.NodeIndex = 0;
            if (self.match(.l_paren)) {
                const type_node = try self.parseType();
                payload_type = type_node;
                while (!self.match(.r_paren)) {
                    if (self.match(.comma)) continue;
                    _ = try self.parseType();
                }
            }

            const v_node = try self.tree.addNode(allocator, .{
                .tag = .variant_def,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .variant_def = .{ .name = v_name, .payload_type = payload_type, .discriminator = 0 } },
            });
            try variants.append(allocator, v_node);

            _ = self.match(.comma);
        }

        return self.tree.addNode(allocator, .{
            .tag = .enum_def,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .enum_def = .{ .name = name, .generic_params = generic_params, .variants = try allocator.dupe(ast.NodeIndex, variants.items) } },
        });
    }

    fn parseEnumAssignDef(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const name_tok = try self.expect(.identifier);
        const name = self.tree.source[name_tok.loc.start..name_tok.loc.end];

        const generic_params = try self.parseGenericParams();

        _ = try self.expect(.assign);

        var variants = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (true) {
            const v_name_tok = try self.expect(.identifier);
            const v_name = self.tree.source[v_name_tok.loc.start..v_name_tok.loc.end];

            var payload_type: ast.NodeIndex = 0;
            var discriminator: ast.NodeIndex = 0;

            if (self.match(.l_paren)) {
                if (self.peek().tag == .literal_int) {
                    discriminator = try self.parseExpression(0);
                    _ = try self.expect(.r_paren);
                } else {
                    const type_node = try self.parseType();
                    payload_type = type_node;
                    while (!self.match(.r_paren)) {
                        if (self.match(.comma)) continue;
                        _ = try self.parseType();
                    }
                }
            }

            const v_node = try self.tree.addNode(allocator, .{
                .tag = .variant_def,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .variant_def = .{ .name = v_name, .payload_type = payload_type, .discriminator = discriminator } },
            });
            try variants.append(allocator, v_node);

            if (!self.match(.pipe)) break;
        }

        return self.tree.addNode(allocator, .{
            .tag = .enum_def,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .enum_def = .{ .name = name, .generic_params = generic_params, .variants = try allocator.dupe(ast.NodeIndex, variants.items) } },
        });
    }

    fn parseFnDef(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const name_tok = try self.expect(.identifier);
        const name = self.tree.source[name_tok.loc.start..name_tok.loc.end];

        const generic_params = try self.parseGenericParams();

        var params = std.ArrayListUnmanaged(ast.NodeIndex){};
        _ = try self.expect(.l_paren);
        while (self.peek().tag != .r_paren) {
            const p_name_tok = try self.expect(.identifier);
            const p_name = self.tree.source[p_name_tok.loc.start..p_name_tok.loc.end];

            const p_type_node = if (self.peek().tag != .r_paren and self.peek().tag != .comma)
                try self.parseType()
            else
                0;

            try params.append(allocator, try self.tree.addNode(allocator, .{
                .tag = .param,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .param = .{ .name = p_name, .type_node = p_type_node } },
            }));

            if (self.peek().tag != .r_paren) {
                _ = try self.expect(.comma);
            }
        }
        _ = try self.expect(.r_paren);

        var return_type: ast.NodeIndex = 0;
        if (self.match(.arrow_out)) {
            return_type = try self.parseType();
        }

        const body = if (self.match(.arrow_fat))
            try self.parseExpression(0)
        else
            try self.parseBlock();

        return self.tree.addNode(allocator, .{
            .tag = .fn_def,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .fn_def = .{ .name = name, .generic_params = generic_params, .params = try allocator.dupe(ast.NodeIndex, params.items), .body = body } },
        });
    }

    fn parseMatchExpr(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        _ = try self.expect(.kw_match);
        const target = try self.parseExpressionNoStructInit(0);
        _ = try self.expect(.l_brace);

        var branches = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (!self.match(.r_brace)) {
            const pattern = try self.parseExpression(0);

            _ = try self.expect(.arrow_fat);

            const body = try self.parseExpression(0);

            const branch_node = try self.tree.addNode(allocator, .{
                .tag = .match_branch,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .match_branch = .{ .pattern = pattern, .body = body } },
            });
            try branches.append(allocator, branch_node);

            _ = self.match(.comma);
        }

        return self.tree.addNode(allocator, .{
            .tag = .match_expr,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .match_expr = .{ .target = target, .branches = branches.items } },
        });
    }

    fn parseBlock(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        _ = try self.expect(.l_brace);

        var statements = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (!self.match(.r_brace)) {
            if (self.match(.kw_defer)) {
                const stmt = try self.parseExpression(0);
                const defer_node = try self.tree.addNode(allocator, .{
                    .tag = .defer_stmt,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .defer_stmt = .{ .expr = stmt } },
                });
                try statements.append(allocator, defer_node);
            } else {
                const stmt = try self.parseExpression(0);
                try statements.append(allocator, stmt);
            }
            while (self.match(.comma) or self.match(.semicolon)) {}
            if (self.peek().tag == .eof) return error.UnexpectedToken;
        }

        return self.tree.addNode(allocator, .{
            .tag = .root,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .root = .{ .children = try allocator.dupe(ast.NodeIndex, statements.items) } },
        });
    }

    fn parseExpression(self: *Parser, min_prec: u8) ParseError!ast.NodeIndex {
        return self.parseExpressionImpl(min_prec, true);
    }

    fn parseExpressionNoStructInit(self: *Parser, min_prec: u8) ParseError!ast.NodeIndex {
        return self.parseExpressionImpl(min_prec, false);
    }

    fn parseExpressionImpl(self: *Parser, min_prec: u8, allow_struct_init: bool) ParseError!ast.NodeIndex {
        var lhs = try self.parsePrefix();

        while (true) {
            const tok = self.peek();

            if (tok.tag == .l_brace and !allow_struct_init) break;

            const prec = self.getInfixPrecedence(tok.tag);
            if (prec == 0 or prec < min_prec) break;

            _ = self.advance();
            lhs = try self.parseInfix(lhs, tok, prec, allow_struct_init);
        }

        return lhs;
    }

    fn parsePrefix(self: *Parser) ParseError!ast.NodeIndex {
        const tok = self.advance();
        const allocator = self.arena.allocator();
        switch (tok.tag) {
            .identifier => {
                const text = self.tree.source[tok.loc.start..tok.loc.end];
                if (std.mem.eql(u8, text, "get")) return self.parsePathGet();
                if (std.mem.eql(u8, text, "set")) return self.parsePathSet();

                return self.tree.addNode(allocator, .{
                    .tag = .identifier,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .identifier = .{ .name = text, .attr = self.getIdentifierAttr(text) } },
                });
            },
            .kw_match => {
                self.pos -= 1;
                return self.parseMatchExpr();
            },
            .l_brace => {
                self.pos -= 1;
                return self.parseStructInit(0);
            },
            .l_bracket => {
                var elements = std.ArrayListUnmanaged(ast.NodeIndex){};
                while (self.peek().tag != .r_bracket) {
                    const elem = try self.parseExpression(0);
                    try elements.append(allocator, elem);
                    if (self.peek().tag != .r_bracket) {
                        _ = try self.expect(.comma);
                    }
                }
                _ = try self.expect(.r_bracket);
                return self.tree.addNode(allocator, .{
                    .tag = .array_literal,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .array_literal = .{ .elements = try allocator.dupe(ast.NodeIndex, elements.items) } },
                });
            },
            .arrow_in => {
                return self.tree.addNode(allocator, .{
                    .tag = .continue_expr,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .continue_expr = .{ .label_token = 0 } },
                });
            },
            .arrow_out => {
                return self.tree.addNode(allocator, .{
                    .tag = .break_expr,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .break_expr = .{ .label_token = 0, .value = 0 } },
                });
            },
            .arrow_fat => {
                const expr = try self.parseExpression(0);
                return self.tree.addNode(allocator, .{
                    .tag = .return_expr,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .return_expr = .{ .value = expr } },
                });
            },
            .literal_int => {
                const text = self.tree.source[tok.loc.start..tok.loc.end];
                const val = try std.fmt.parseInt(i64, text, 0);
                return self.tree.addNode(allocator, .{
                    .tag = .literal_int,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .literal_int = val },
                });
            },
            .literal_float => {
                const text = self.tree.source[tok.loc.start..tok.loc.end];
                const val = try std.fmt.parseFloat(f64, text);
                return self.tree.addNode(allocator, .{
                    .tag = .literal_float,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .literal_float = val },
                });
            },
            .literal_text => {
                const text = self.tree.source[tok.loc.start + 1 .. tok.loc.end - 1];
                return self.tree.addNode(allocator, .{
                    .tag = .literal_text,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .literal_text = text },
                });
            },
            .l_paren => {
                const expr = try self.parseExpression(0);
                if (self.match(.comma)) {
                    var elements = std.ArrayListUnmanaged(ast.NodeIndex){};
                    try elements.append(allocator, expr);
                    while (self.peek().tag != .r_paren) {
                        const elem = try self.parseExpression(0);
                        try elements.append(allocator, elem);
                        if (self.peek().tag != .r_paren) {
                            _ = try self.expect(.comma);
                        }
                    }
                    _ = try self.expect(.r_paren);
                    return self.tree.addNode(allocator, .{
                        .tag = .tuple_literal,
                        .main_token = @as(u32, @intCast(self.pos - 1)),
                        .data = .{ .tuple_literal = .{ .elements = try allocator.dupe(ast.NodeIndex, elements.items) } },
                    });
                }
                _ = try self.expect(.r_paren);
                return expr;
            },
            .dot => {
                const tok_next = self.peek();
                if (tok_next.tag == .identifier) {
                    _ = self.advance();
                    const name = self.tree.source[tok_next.loc.start..tok_next.loc.end];
                    return self.tree.addNode(allocator, .{
                        .tag = .identifier,
                        .main_token = @as(u32, @intCast(self.pos - 1)),
                        .data = .{ .identifier = .{ .name = name, .attr = .{} } },
                    });
                } else if (tok_next.tag == .literal_int) {
                    _ = self.advance();
                    const name = self.tree.source[tok_next.loc.start..tok_next.loc.end];
                    return self.tree.addNode(allocator, .{
                        .tag = .identifier,
                        .main_token = @as(u32, @intCast(self.pos - 1)),
                        .data = .{ .identifier = .{ .name = name, .attr = .{} } },
                    });
                }
                return error.ExpectedToken;
            },
            .kw_if => return self.parseIfExpr(),
            .kw_loop => return self.parseLoopExpr(),
            else => return error.UnexpectedToken,
        }
    }

    fn parseStructInit(self: *Parser, type_node_idx: ast.NodeIndex) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        std.debug.print("DEBUG: parseStructInit starting with type_node_idx: {d}\\n", .{type_node_idx});
        _ = try self.expect(.l_brace);
        var entries = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (!self.match(.r_brace)) {
            while (self.match(.comma) or self.match(.semicolon)) {}
            if (self.peek().tag == .r_brace) {
                _ = self.advance();
                break;
            }

            const entry = try self.parseSetEntry();
            try entries.append(allocator, entry);
            _ = self.match(.comma);
            _ = self.match(.semicolon);
        }

        return self.tree.addNode(allocator, .{
            .tag = .struct_init,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .struct_init = .{ .type_node = type_node_idx, .entries = try allocator.dupe(ast.NodeIndex, entries.items) } },
        });
    }

    fn getIdentifierAttr(_: *Parser, text: []const u8) ast.IdentifierAttr {
        var attr = ast.IdentifierAttr{};
        if (text[0] == '.') attr.is_private = true;
        if (text[0] == '_' or (text[0] == '.' and text.len > 1 and text[1] == '_')) {
            attr.is_immutable = true;
        }
        return attr;
    }

    fn parseSetEntry(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const path = if (self.peek().tag == .l_bracket)
            try self.parseExpression(0)
        else blk: {
            const key_tok = try self.expect(.identifier);
            const key = self.tree.source[key_tok.loc.start..key_tok.loc.end];
            std.debug.print("DEBUG: parseSetEntry key: '{s}', next tok: {any}\\n", .{ key, self.peek().tag });
            break :blk try self.tree.addNode(allocator, .{
                .tag = .identifier,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .identifier = .{ .name = key, .attr = .{} } },
            });
        };

        _ = try self.expect(.colon);
        const val = try self.parseExpression(0);

        return self.tree.addNode(allocator, .{
            .tag = .set_entry,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .set_entry = .{ .path = path, .value = val } },
        });
    }

    fn parsePathGet(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        _ = try self.expect(.l_paren);
        const target = try self.parseExpression(0);
        var path = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (self.match(.comma)) {
            const segment = try self.parseExpression(0);
            try path.append(allocator, segment);
        }
        _ = try self.expect(.r_paren);
        return self.tree.addNode(allocator, .{
            .tag = .path_get,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .path_get = .{ .target = target, .path = try allocator.dupe(ast.NodeIndex, path.items) } },
        });
    }

    fn parsePathSequence(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        var segments = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (true) {
            const segment = try self.parseExpression(0);
            try segments.append(allocator, segment);
            if (!self.match(.comma)) break;
        }
        _ = try self.expect(.r_bracket);
        return self.tree.addNode(allocator, .{
            .tag = .path_sequence,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .path_sequence = .{ .segments = try allocator.dupe(ast.NodeIndex, segments.items) } },
        });
    }

    fn parsePathSet(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        _ = try self.expect(.l_paren);
        const target = try self.parseExpression(0);
        _ = try self.expect(.comma);
        if (self.match(.l_brace)) {
            var entries = std.ArrayListUnmanaged(ast.NodeIndex){};
            while (true) {
                const path_seq = try self.parseExpression(0);
                _ = try self.expect(.colon);
                const value = try self.parseExpression(0);
                const entry = try self.tree.addNode(allocator, .{
                    .tag = .set_entry,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .set_entry = .{ .path = path_seq, .value = value } },
                });
                try entries.append(allocator, entry);
                if (!self.match(.comma)) break;
            }
            _ = try self.expect(.r_brace);
            _ = try self.expect(.r_paren);
            return self.tree.addNode(allocator, .{
                .tag = .path_set,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .path_set = .{ .target = target, .entries = try allocator.dupe(ast.NodeIndex, entries.items) } },
            });
        } else {
            const field = try self.parseExpression(0);
            _ = try self.expect(.comma);
            const value = try self.parseExpression(0);
            _ = try self.expect(.r_paren);

            const entry = try self.tree.addNode(allocator, .{
                .tag = .set_entry,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .set_entry = .{ .path = field, .value = value } },
            });
            const entries = try allocator.alloc(ast.NodeIndex, 1);
            entries[0] = entry;

            return self.tree.addNode(allocator, .{
                .tag = .path_set,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .path_set = .{ .target = target, .entries = entries } },
            });
        }
    }

    fn parseInfix(self: *Parser, lhs: ast.NodeIndex, op_tok: token.Token, prec: u8, allow_struct_init: bool) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        switch (op_tok.tag) {
            .plus, .minus, .asterisk, .slash, .equal_equal, .not_equal, .greater, .greater_equal, .less_equal => {
                const rhs = try self.parseExpressionImpl(prec + 1, allow_struct_init);
                return self.tree.addNode(allocator, .{
                    .tag = .binary_op,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .binary_op = .{ .lhs = lhs, .rhs = rhs } },
                });
            },
            .assign, .assign_init => {
                const rhs = try self.parseExpressionImpl(prec - 1, allow_struct_init);
                return self.tree.addNode(allocator, .{
                    .tag = if (op_tok.tag == .assign) .assign else .assign_init,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = if (op_tok.tag == .assign) .{ .assign = .{ .lhs = lhs, .rhs = rhs } } else .{ .assign_init = .{ .lhs = lhs, .rhs = rhs } },
                });
            },
            .l_paren => return self.parseCall(lhs),
            .l_brace => {
                const tag = self.tree.nodes.items[lhs].tag;
                if (tag == .identifier or tag == .type_apply) {
                    self.pos -= 1;
                    return self.parseStructInit(lhs);
                }
                return error.UnexpectedToken;
            },
            .less => {
                if (self.tree.nodes.items[lhs].tag == .identifier) {
                    const text = self.tree.nodes.items[lhs].data.identifier.name;
                    var params = std.ArrayListUnmanaged(ast.NodeIndex){};
                    while (self.peek().tag != .greater) {
                        try params.append(allocator, try self.parseType());
                        if (self.peek().tag != .greater) {
                            _ = try self.expect(.comma);
                        }
                    }
                    _ = try self.expect(.greater);
                    return self.tree.addNode(allocator, .{
                        .tag = .type_apply,
                        .main_token = @as(u32, @intCast(self.pos - 1)),
                        .data = .{ .type_apply = .{ .base_name = text, .params = try allocator.dupe(ast.NodeIndex, params.items) } },
                    });
                } else {
                    const rhs = try self.parseExpressionImpl(3 + 1, allow_struct_init);
                    return self.tree.addNode(allocator, .{
                        .tag = .binary_op,
                        .main_token = @as(u32, @intCast(self.pos - 1)),
                        .data = .{ .binary_op = .{ .lhs = lhs, .rhs = rhs } },
                    });
                }
            },
            .dot => {
                const tok_next = self.peek();
                var name: []const u8 = undefined;
                if (tok_next.tag == .identifier or tok_next.tag == .literal_int) {
                    _ = self.advance();
                    name = self.tree.source[tok_next.loc.start..tok_next.loc.end];
                } else {
                    return error.ExpectedToken;
                }
                const segment = try self.tree.addNode(allocator, .{
                    .tag = .identifier,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .identifier = .{ .name = name, .attr = .{} } },
                });
                const path = try allocator.alloc(ast.NodeIndex, 1);
                path[0] = segment;
                return self.tree.addNode(allocator, .{
                    .tag = .path_get,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .path_get = .{ .target = lhs, .path = path } },
                });
            },
            .arrow_out => {
                var label_tok: u32 = 0;
                if (self.peek().tag == .identifier) {
                    _ = self.advance();
                    label_tok = @as(u32, @intCast(self.pos - 1));
                }
                return self.tree.addNode(allocator, .{
                    .tag = .break_expr,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .break_expr = .{ .label_token = label_tok, .value = lhs } },
                });
            },
            else => return lhs,
        }
    }

    fn parseIfExpr(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const cond = try self.parseExpressionNoStructInit(0);
        const then_body = try self.parseBlock();
        var else_body: ast.NodeIndex = 0;
        if (self.match(.kw_else)) {
            if (self.peek().tag == .kw_if) {
                else_body = try self.parseExpression(0);
            } else {
                else_body = try self.parseBlock();
            }
        }
        return self.tree.addNode(allocator, .{
            .tag = .if_expr,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .if_expr = .{ .cond = cond, .then_body = then_body, .else_body = else_body } },
        });
    }

    fn parseLoopExpr(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        var label_tok: u32 = 0;
        _ = try self.expect(.l_brace);
        if (self.match(.hash_tag)) {
            _ = try self.expect(.identifier);
            label_tok = @as(u32, @intCast(self.pos - 1));
        }

        var statements = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (!self.match(.r_brace)) {
            const stmt = try self.parseExpression(0);
            try statements.append(allocator, stmt);
            while (self.match(.comma) or self.match(.semicolon)) {}
            if (self.peek().tag == .eof) return error.UnexpectedToken;
        }

        const body = try self.tree.addNode(allocator, .{
            .tag = .root,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .root = .{ .children = try allocator.dupe(ast.NodeIndex, statements.items) } },
        });

        return self.tree.addNode(allocator, .{
            .tag = .loop_expr,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .loop_expr = .{ .label_token = label_tok, .body = body } },
        });
    }

    fn peek(self: *Parser) token.Token {
        if (self.pos >= self.tokens.len) return .{ .tag = .eof, .loc = undefined };
        return self.tokens[self.pos];
    }

    fn advance(self: *Parser) token.Token {
        const tok = self.peek();
        self.pos += 1;
        return tok;
    }

    fn match(self: *Parser, tag: token.TokenTag) bool {
        if (self.peek().tag == tag) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn expect(self: *Parser, tag: token.TokenTag) !token.Token {
        const tok = self.advance();
        if (tok.tag != tag) return error.ExpectedToken;
        return tok;
    }

    fn getInfixPrecedence(_: *Parser, tag: token.TokenTag) u8 {
        return switch (tag) {
            .dot => 100,
            .less => 8, // 类型应用优先级高于调用
            .l_paren, .l_brace => 7,
            .arrow_out => 1,
            .assign, .assign_init => 2,
            .equal_equal, .not_equal, .greater, .greater_equal, .less_equal => 3,
            .plus, .minus => 4,
            .asterisk, .slash => 5,
            else => 0,
        };
    }

    fn peekAt(self: *Parser, offset: usize) token.Token {
        if (self.pos + offset >= self.tokens.len) return self.tokens[self.tokens.len - 1];
        return self.tokens[self.pos + offset];
    }

    fn parseGenericParams(self: *Parser) ParseError![]const ast.NodeIndex {
        const allocator = self.arena.allocator();
        var params = std.ArrayListUnmanaged(ast.NodeIndex){};

        if (self.match(.less)) {
            while (self.peek().tag != .greater) {
                const name_tok = try self.expect(.identifier);
                const name = self.tree.source[name_tok.loc.start..name_tok.loc.end];

                const constraints = std.ArrayListUnmanaged(ast.NodeIndex){};

                const param = try self.tree.addNode(allocator, .{
                    .tag = .generic_param,
                    .main_token = @as(u32, @intCast(self.pos - 1)),
                    .data = .{ .generic_param = .{ .name = name, .constraints = try allocator.dupe(ast.NodeIndex, constraints.items) } },
                });
                try params.append(allocator, param);

                if (self.peek().tag != .greater) {
                    _ = try self.expect(.comma);
                }
            }
            _ = try self.expect(.greater);
        }
        return try allocator.dupe(ast.NodeIndex, params.items);
    }

    fn parseConstraintBlock(self: *Parser, target_name: []const u8) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        // const target_tok = try self.expect(.identifier); // 已经在外面解析了
        // const target_name = self.tree.source[target_tok.loc.start..target_tok.loc.end];

        // 目前简单处理：认为约束块后面紧跟定义，暂存到 Sema 进行关联
        // 实际上可以作为装饰器节点
        _ = try self.expect(.l_brace);
        var fields = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (self.peek().tag != .r_brace) {
            const f_name_tok = try self.expect(.identifier);
            const f_name = self.tree.source[f_name_tok.loc.start..f_name_tok.loc.end];
            const f_type = try self.parseType();

            try fields.append(allocator, try self.tree.addNode(allocator, .{
                .tag = .field_def,
                .main_token = @as(u32, @intCast(self.pos - 2)),
                .data = .{ .field_def = .{ .name = f_name, .type_node = f_type, .attr = .{} } },
            }));
            while (self.match(.comma) or self.match(.semicolon)) {}
        }
        _ = try self.expect(.r_brace);

        const constraint_struct = try self.tree.addNode(allocator, .{
            .tag = .struct_def,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .struct_def = .{ .name = target_name, .fields = try allocator.dupe(ast.NodeIndex, fields.items), .generic_params = &[_]ast.NodeIndex{} } },
        });

        return constraint_struct;
    }

    fn parseType(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();

        if (self.match(.l_paren)) {
            var elements = std.ArrayListUnmanaged(ast.NodeIndex){};
            while (self.peek().tag != .r_paren) {
                try elements.append(allocator, try self.parseType());
                if (self.peek().tag != .r_paren) {
                    _ = try self.expect(.comma);
                }
            }
            _ = try self.expect(.r_paren);
            return self.tree.addNode(allocator, .{
                .tag = .tuple_type,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .tuple_type = .{ .elements = try allocator.dupe(ast.NodeIndex, elements.items) } },
            });
        }

        const base_tok = self.advance();
        if (base_tok.tag != .identifier and base_tok.tag != .kw_bool) return error.ExpectedToken;
        const base_name = self.tree.source[base_tok.loc.start..base_tok.loc.end];

        var params = std.ArrayListUnmanaged(ast.NodeIndex){};
        if (self.match(.less)) {
            while (self.peek().tag != .greater) {
                try params.append(allocator, try self.parseType());
                if (self.peek().tag != .greater) {
                    _ = try self.expect(.comma);
                }
            }
            _ = try self.expect(.greater);
        }

        if (params.items.len == 0) {
            // 简单类型，也包装成 type_apply 方面 Sema 统一处理
            return self.tree.addNode(allocator, .{
                .tag = .type_apply,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .type_apply = .{ .base_name = base_name, .params = &[_]ast.NodeIndex{} } },
            });
        }

        return self.tree.addNode(allocator, .{
            .tag = .type_apply,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .type_apply = .{ .base_name = base_name, .params = try allocator.dupe(ast.NodeIndex, params.items) } },
        });
    }

    fn parseCall(self: *Parser, target_node: ast.NodeIndex) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        var args = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (!self.match(.r_paren)) {
            const arg = try self.parseExpression(0);
            try args.append(allocator, arg);
            _ = self.match(.comma);
        }
        return self.tree.addNode(allocator, .{
            .tag = .call,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .call = .{ .base_node = target_node, .args = try allocator.dupe(ast.NodeIndex, args.items) } },
        });
    }
};
