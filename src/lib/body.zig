const std = @import("std");

pub const Body = @This();

buffer: std.ArrayList(u8),

pub fn init(allocator: std.mem.Allocator) Body {
    return Body{
        .buffer = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: *Body) void {
    self.buffer.deinit();
}

pub fn set(self: *Body, payload: anytype) !void {
    try std.json.stringify(payload, .{}, self.buffer.writer());
}

pub fn get(self: *Body, comptime T: type) !T {
    const parsed = std.json.parseFromSliceLeaky(T, self.allocator, self.buffer.items, .{}) catch |e| {
        std.log.err("Error parsing json: {?}", .{e});
        return error.InvalidRange;
    };
    return parsed;
}
