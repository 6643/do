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

    pub fn parse(self: *Parser) !ast.NodeIndex {
        const allocator = self.arena.allocator();
        var root_nodes = std.ArrayListUnmanaged(ast.NodeIndex){};

        while (self.peek().tag != .eof) {
            std.debug.print("PARSER: next top level, current pos: {d}, tag: {any}\n", .{ self.pos, self.peek().tag });
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
        if (tok.tag == .hash_tag) return self.parseConstraintDef();
        if (tok.tag == .kw_loop) return self.parseLoopExpr();
        
        if (tok.tag == .identifier) {
            if (try self.isDefinition()) return self.parseNamedDefinition();
        }

        return self.parseExpression(0);
    }

    fn isDefinition(self: *Parser) !bool {
        var i: usize = 1;
        std.debug.print("DEBUG: isDefinition sniffing starting at pos {d}\n", .{self.pos});
        // Skip generics <...>
        if (self.peekAt(i).tag == .less) {
            i += 1;
            var depth: u32 = 1;
            while (depth > 0) {
                const t = self.peekAt(i);
                if (t.tag == .less) depth += 1;
                if (t.tag == .greater) depth -= 1;
                if (t.tag == .eof) return false;
                i += 1;
            }
        }
        
        const next = self.peekAt(i).tag;
        std.debug.print("DEBUG: isDefinition next tag: {any}\n", .{next});
        if (next == .l_brace or next == .assign) return true;
        
        if (next == .l_paren) {
            // Skip params (...)
            i += 1;
            var depth: u32 = 1;
            while (depth > 0) {
                const t = self.peekAt(i);
                if (t.tag == .l_paren) depth += 1;
                if (t.tag == .r_paren) depth -= 1;
                if (t.tag == .eof) return false;
                i += 1;
            }
            // Check for body or return type
            const post = self.peekAt(i).tag;
            std.debug.print("DEBUG: isDefinition post-paren tag: {any}\n", .{post});
            return post == .l_brace or post == .arrow_out or post == .arrow_fat;
        }
        
        return false;
    }

    fn parseNamedDefinition(self: *Parser) ParseError!ast.NodeIndex {
        var i: usize = 1;
        if (self.peekAt(i).tag == .less) {
            var depth: u32 = 1; i += 1;
            while (depth > 0) {
                const t = self.peekAt(i);
                if (t.tag == .less) depth += 1;
                if (t.tag == .greater) depth -= 1;
                i += 1;
            }
        }
        
        const next = self.peekAt(i);
        if (next.tag == .assign) {
            if (self.peekAt(i + 1).tag == .hash_tag) return self.parseFFIDecl();
            return self.parseUnionAssignDef();
        }
        if (next.tag == .l_paren) return self.parseFnDef();
        if (next.tag == .l_brace) {
            if (self.peekAt(i + 1).tag == .dot) return self.parseUnionDef();
            return self.parseStructDef();
        }
        return self.parseExpression(0);
    }

    fn parseFFIDecl(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const name_tok = try self.expect(.identifier);
        const name = self.tree.source[name_tok.loc.start..name_tok.loc.end];
        _ = try self.expect(.assign);
        _ = try self.expect(.hash_tag);
        
        const module_tok = try self.expect(.identifier);
        const module_name = self.tree.source[module_tok.loc.start..module_tok.loc.end];
        _ = try self.expect(.dot);
        const fn_tok = try self.expect(.identifier);
        const fn_name = self.tree.source[fn_tok.loc.start..fn_tok.loc.end];
        
        _ = try self.expect(.l_paren);
        var params = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (self.peek().tag != .r_paren) {
            try params.append(allocator, try self.parseType());
            if (!self.match(.comma)) break;
        }
        _ = try self.expect(.r_paren);
        
        var return_type: ast.NodeIndex = 0;
        if (self.match(.arrow_out)) {
            return_type = try self.parseType();
        }
        
        return self.tree.addNode(allocator, .{
            .tag = .ffi_decl,
            .main_token = @intCast(self.pos - 1),
            .data = .{ .ffi_decl = .{
                .name = name,
                .module_name = module_name,
                .fn_name = fn_name,
                .params = try allocator.dupe(ast.NodeIndex, params.items),
                .return_type = return_type,
            } }
        });
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

    fn parseUnionDef(self: *Parser) ParseError!ast.NodeIndex {
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
            .tag = .union_def,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .union_def = .{ .name = name, .generic_params = generic_params, .variants = try allocator.dupe(ast.NodeIndex, variants.items) } },
        });
    }

    fn parseUnionAssignDef(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const name_tok = try self.expect(.identifier);
        const name = self.tree.source[name_tok.loc.start..name_tok.loc.end];

        const generic_params = try self.parseGenericParams();

        _ = try self.expect(.assign);

        var variants = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (true) {
            _ = try self.expect(.dot);
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
            .tag = .union_def,
            .main_token = @as(u32, @intCast(self.pos - 1)),
            .data = .{ .union_def = .{ .name = name, .generic_params = generic_params, .variants = try allocator.dupe(ast.NodeIndex, variants.items) } },
        });
    }

    fn parseFnDef(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const name_tok = try self.expect(.identifier);
        const name = self.tree.source[name_tok.loc.start..name_tok.loc.end];
        std.debug.print("PARSER: entering parseFnDef for {s}\n", .{name});

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
            std.debug.print("PARSER: parsing return type\n", .{});
            return_type = try self.parseType();
        }

        std.debug.print("PARSER: finished signature, starting body\n", .{});
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
        std.debug.print("PARSER: entering parseBlock\n", .{});

        var statements = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (!self.match(.r_brace)) {
            std.debug.print("PARSER: next stmt tok: {any}\n", .{self.peek().tag});
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
        const tok = self.peek();
        const allocator = self.arena.allocator();

        return switch (tok.tag) {
            .literal_int, .literal_float, .literal_text => self.parseLiteral(),
            .identifier => self.parseIdentifierOrBuiltin(),
            .kw_match => self.parseMatchExpr(),
            .l_brace => blk: { self.pos += 1; break :blk self.parseStructInit(0); },
            .l_bracket => self.parseArrayLiteral(),
            .l_paren => self.parseGroupOrTuple(),
            .kw_if => self.parseIfExpr(),
            .kw_loop => self.parseLoopExpr(),
            .arrow_in => blk: { _ = self.advance(); break :blk self.tree.addNode(allocator, .{ .tag = .continue_expr, .main_token = @intCast(self.pos-1), .data = .{ .continue_expr = .{ .label_token = 0 } } }); },
            .arrow_out => blk: { _ = self.advance(); break :blk self.tree.addNode(allocator, .{ .tag = .break_expr, .main_token = @intCast(self.pos-1), .data = .{ .break_expr = .{ .label_token = 0, .value = 0 } } }); },
            .arrow_fat => blk: { _ = self.advance(); break :blk self.tree.addNode(allocator, .{ .tag = .return_expr, .main_token = @intCast(self.pos-1), .data = .{ .return_expr = .{ .value = try self.parseExpression(0) } } }); },
            .dot => self.parseUnionLiteral(),
            else => error.UnexpectedToken,
        };
    }

    fn parseLiteral(self: *Parser) ParseError!ast.NodeIndex {
        const tok = self.advance();
        const allocator = self.arena.allocator();
        const text = self.tree.source[tok.loc.start..tok.loc.end];
        return switch (tok.tag) {
            .literal_int => self.tree.addNode(allocator, .{ .tag = .literal_int, .main_token = @intCast(self.pos-1), .data = .{ .literal_int = try std.fmt.parseInt(i64, text, 0) } }),
            .literal_float => self.tree.addNode(allocator, .{ .tag = .literal_float, .main_token = @intCast(self.pos-1), .data = .{ .literal_float = try std.fmt.parseFloat(f64, text) } }),
            .literal_text => self.tree.addNode(allocator, .{ .tag = .literal_text, .main_token = @intCast(self.pos-1), .data = .{ .literal_text = text[1 .. text.len - 1] } }),
            else => unreachable,
        };
    }

    fn parseIdentifierOrBuiltin(self: *Parser) ParseError!ast.NodeIndex {
        const tok = self.advance();
        const text = self.tree.source[tok.loc.start..tok.loc.end];
        return self.tree.addNode(self.arena.allocator(), .{
            .tag = .identifier,
            .main_token = @intCast(self.pos - 1),
            .data = .{ .identifier = .{ .name = text, .attr = self.getIdentifierAttr(text) } },
        });
    }

    fn parseUnionLiteral(self: *Parser) ParseError!ast.NodeIndex {
        _ = try self.expect(.dot);
        const tok = try self.expect(.identifier);
        const name = self.tree.source[tok.loc.start..tok.loc.end];
        return self.tree.addNode(self.arena.allocator(), .{
            .tag = .union_literal,
            .main_token = @intCast(self.pos - 1),
            .data = .{ .union_literal = name },
        });
    }

    fn parseArrayLiteral(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        _ = try self.expect(.l_bracket);
        var elements = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (self.peek().tag != .r_bracket) {
            try elements.append(allocator, try self.parseExpression(0));
            if (!self.match(.comma)) break;
        }
        _ = try self.expect(.r_bracket);
        return self.tree.addNode(allocator, .{
            .tag = .array_literal,
            .main_token = @intCast(self.pos - 1),
            .data = .{ .array_literal = .{ .elements = try allocator.dupe(ast.NodeIndex, elements.items) } },
        });
    }

    fn parseGroupOrTuple(self: *Parser) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        _ = try self.expect(.l_paren);
        const first = try self.parseExpression(0);
        if (self.match(.comma)) {
            var elements = std.ArrayListUnmanaged(ast.NodeIndex){};
            try elements.append(allocator, first);
            while (self.peek().tag != .r_paren) {
                try elements.append(allocator, try self.parseExpression(0));
                if (!self.match(.comma)) break;
            }
            _ = try self.expect(.r_paren);
            return self.tree.addNode(allocator, .{
                .tag = .tuple_literal,
                .main_token = @intCast(self.pos - 1),
                .data = .{ .tuple_literal = .{ .elements = try allocator.dupe(ast.NodeIndex, elements.items) } },
            });
        }
        _ = try self.expect(.r_paren);
        return first;
    }

    fn parseStructInit(self: *Parser, type_node_idx: ast.NodeIndex) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
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
        else if (self.peek().tag == .literal_int) blk: {
            const key_tok = try self.expect(.literal_int);
            const key = self.tree.source[key_tok.loc.start..key_tok.loc.end];
            break :blk try self.tree.addNode(allocator, .{
                .tag = .literal_int,
                .main_token = @as(u32, @intCast(self.pos - 1)),
                .data = .{ .literal_int = try std.fmt.parseInt(i64, key, 0) },
            });
        } else blk: {
            const key_tok = try self.expect(.identifier);
            const key = self.tree.source[key_tok.loc.start..key_tok.loc.end];
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

    fn parseInfix(self: *Parser, lhs: ast.NodeIndex, op_tok: token.Token, prec: u8, allow_struct_init: bool) ParseError!ast.NodeIndex {
        const allocator = self.arena.allocator();
        const op_idx = @as(u32, @intCast(self.pos - 1));
        return switch (op_tok.tag) {
            .dot => blk: {
                const tok = try self.expect(.identifier);
                const name = self.tree.source[tok.loc.start..tok.loc.end];
                const segment = try self.tree.addNode(allocator, .{
                    .tag = .identifier,
                    .main_token = @intCast(self.pos - 1),
                    .data = .{ .identifier = .{ .name = name, .attr = .{} } },
                });
                const path = try allocator.alloc(ast.NodeIndex, 1);
                path[0] = segment;
                break :blk self.tree.addNode(allocator, .{
                    .tag = .path_get,
                    .main_token = op_idx,
                    .data = .{ .path_get = .{ .target = lhs, .path = path } },
                });
            },
            .plus, .minus, .asterisk, .slash, .percent, .equal_equal, .not_equal, 
            .greater, .greater_equal, .less_equal, .l_shift, .r_shift, .pipe => blk: {
                const rhs = try self.parseExpressionImpl(prec + 1, allow_struct_init);
                break :blk self.tree.addNode(allocator, .{
                    .tag = .binary_op,
                    .main_token = op_idx,
                    .data = .{ .binary_op = .{ .lhs = lhs, .rhs = rhs } },
                });
            },
            .assign, .assign_init => blk: {
                const rhs = try self.parseExpressionImpl(prec - 1, allow_struct_init);
                break :blk self.tree.addNode(allocator, .{
                    .tag = if (op_tok.tag == .assign) .assign else .assign_init,
                    .main_token = op_idx,
                    .data = if (op_tok.tag == .assign) .{ .assign = .{ .lhs = lhs, .rhs = rhs } } else .{ .assign_init = .{ .lhs = lhs, .rhs = rhs } },
                });
            },
            .l_paren => self.parseCall(lhs),
            .l_brace => self.handleBraceInfix(lhs),
            .less => self.handleLessInfix(lhs, allow_struct_init),
            else => lhs,
        };
    }

    fn handleBraceInfix(self: *Parser, lhs: ast.NodeIndex) !ast.NodeIndex {
        const tag = self.tree.nodes.items[lhs].tag;
        if (tag != .identifier and tag != .type_apply) return error.UnexpectedToken;
        self.pos -= 1;
        return self.parseStructInit(lhs);
    }

    fn handleLessInfix(self: *Parser, lhs: ast.NodeIndex, allow_struct_init: bool) !ast.NodeIndex {
        const allocator = self.arena.allocator();
        if (self.tree.nodes.items[lhs].tag != .identifier) {
            const rhs = try self.parseExpressionImpl(3 + 1, allow_struct_init);
            return self.tree.addNode(allocator, .{
                .tag = .binary_op,
                .main_token = @intCast(self.pos - 1),
                .data = .{ .binary_op = .{ .lhs = lhs, .rhs = rhs } },
            });
        }
        
        const name = self.tree.nodes.items[lhs].data.identifier.name;
        var params = std.ArrayListUnmanaged(ast.NodeIndex){};
        while (self.peek().tag != .greater) {
            try params.append(allocator, try self.parseType());
            if (!self.match(.comma)) break;
        }
        _ = try self.expect(.greater);
        return self.tree.addNode(allocator, .{
            .tag = .type_apply,
            .main_token = @intCast(self.pos - 1),
            .data = .{ .type_apply = .{ .base_name = name, .params = try allocator.dupe(ast.NodeIndex, params.items) } },
        });
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
        _ = try self.expect(.kw_loop);
        
        var label_tok: u32 = 0;
        if (self.match(.hash_tag)) {
            const tok = try self.expect(.identifier);
            label_tok = @as(u32, @intCast(self.pos - 1));
            _ = tok;
        }
        
        _ = try self.expect(.l_brace);

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
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn expect(self: *Parser, tag: token.TokenTag) !token.Token {
        const tok = self.advance();
        if (tok.tag != tag) {
            return error.ExpectedToken;
        }
        return tok;
    }

    fn getInfixPrecedence(_: *Parser, tag: token.TokenTag) u8 {
        return switch (tag) {
            .dot => 100,
            .less => 8, // 类型应用优先级高于调用
            .l_paren, .l_brace => 7,
            .arrow_out => 1,
            .assign, .assign_init => 2,
            .equal_equal, .not_equal, .greater, .greater_equal, .less_equal, .l_shift, .r_shift, .pipe => 3,
            .plus, .minus => 4,
            .asterisk, .slash, .percent => 5,
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
        const tok = self.peek();
        std.debug.print("PARSER: entering parseType at tok: {any}\n", .{tok.tag});
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
        
        if (base_tok.tag == .literal_int) {
             const text = self.tree.source[base_tok.loc.start..base_tok.loc.end];
             const val = try std.fmt.parseInt(i64, text, 0);
             return self.tree.addNode(allocator, .{
                 .tag = .literal_int,
                 .main_token = @as(u32, @intCast(self.pos - 1)),
                 .data = .{ .literal_int = val },
             });
        }

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
