const std = @import("std");
const json = std.json;
const Buffer = @import("buffer").Buffer;
const Allocator = std.mem.Allocator;

const Body = @This();

buffer: Buffer = undefined,

pub fn new() !*Body {
 return Body{};
}

pub fn get(self: *Body, allocator: Allocator, comptime T: type) !T {
    const parsed =  json.parseFromSliceLeaky(T, allocator, self.buffer.str(), .{}) 
    catch |e| {
        std.log.err("Error parsing json: {?}", .{e});
        return error.InvalidRange;
    };
    return parsed;
}

pub fn set(self: *Body, payload: anytype) !void {
    try std.json.stringify(payload, .{}, self.buffer.writer());
}
