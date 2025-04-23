const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;

pub const Pair = struct {
    name: []const u8,
    value: []const u8,
};

pub const Pairs = struct {
    allocator: mem.Allocator,
    list: std.ArrayList(Pair),

    pub fn init(allocator: mem.Allocator) !Pairs {
        return .{
            .allocator = allocator,
            .list = std.ArrayList(Pair).init(allocator),
        };
    }

    pub fn deinit(self: *Pairs) void {
        for (self.list.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }

        self.list.deinit();
    }

    pub fn add(self: *Pairs, name: []const u8, value: []const u8) !void {
        const duped_name = try self.allocator.dupe(u8, name);
        const duped_value = try self.allocator.dupe(u8, value);

        try self.list.append(.{
            .name = duped_name,
            .value = duped_value,
        });
    }

    pub fn get(self: *Pairs, name: []const u8) ?[]const u8 {
        for (self.list.items) |header| {
            if (ascii.eqlIgnoreCase(header.name, name)) {
                return header.value;
            }
        }

        return null;
    }
};
