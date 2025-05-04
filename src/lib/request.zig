const std = @import("std");
const mem = std.mem;

const aio = @import("aio");
const coro = @import("coro");
const u = @import("./utils.zig");

const Chunks = @import("./chunks.zig").Chunks;
const Pairs = @import("./pairs.zig").Pairs;
const Method = @import("./method.zig").Method;
const Version = @import("./version.zig").Version;
const Body = @import("body.zig");

pub const Request = @This();

allocator: mem.Allocator,
socket: std.posix.socket_t = undefined,
method: Method = undefined,
version: Version = undefined,
path: []const u8 = undefined,
route: std.ArrayList(u8),
headers: Pairs,
params: Pairs,
body: Body,

pub fn new(allocator: std.mem.Allocator, socket: std.posix.socket_t) !Request {
    return Request{
        .socket = socket,
        .allocator = allocator,
        .headers = try Pairs.init(allocator),
        .params = try Pairs.init(allocator),
        .route = std.ArrayList(u8).init(allocator),
        .body = Body.init(allocator),
    };
}

pub fn init(allocator: std.mem.Allocator) !Request {

    return Request{
        .allocator = allocator,
        .headers = try Pairs.init(allocator),
        .params = try Pairs.init(allocator),
        .route = std.ArrayList(u8).init(allocator),
        .body = Body.init(allocator),
    };

}

pub fn getHeader(self: *Request, name: []const u8) ?[]const u8 {
    return self.headers.get(name);
}

pub fn getParam(self: *Request, name: []const u8) ?[]const u8 {
    return self.params.get(name);
}

pub fn read(self: *Request) !void {
    const buff = try self.allocator.alloc(u8, 4096);
    var len: usize = 0;

    try coro.io.single(.recv, .{ .socket = self.socket, .buffer = buff, .out_read = &len });

    var lines = mem.splitSequence(u8, buff, "\r\n");

    //get first line of request
    const first_line = lines.next() orelse return error.InvalidRequest;

    var flit = std.mem.splitScalar(u8, first_line, ' ');

    if (flit.next()) |method| {
        self.method = try Method.fromString(method);
    } else {
        std.log.err("No Method in: {s}", .{buff});
    }

    if (flit.next()) |path| {
        if (mem.eql(u8, path, "/")) {
            self.path = try self.allocator.dupe(u8, "/index.html");
        } else {
            self.path = try self.allocator.dupe(u8, path);
        }
    } else {
        std.log.err("No Path in: {s}", .{buff});
    }

    if (flit.next()) |version| {
        self.version = try Version.fromString(version);
    } else {
        std.log.err("No Version in: {s}", .{buff});
    }

    //get request parameters and url route for api patameters
    var path_iter = mem.splitScalar(u8, self.path, '?');
    //skip contents before '?'
    if (path_iter.next()) |segs| {
        if (mem.startsWith(u8, segs, "/api")) {
            var seg_iter = std.mem.splitSequence(u8, segs, "/");
            _ = seg_iter.next().?;
            _ = seg_iter.next().?;
            const resource = seg_iter.next().?;
            try self.route.writer().print("/{s}", .{resource});
        }
    }

    if (path_iter.next()) |params| {
        var keyvals = mem.splitScalar(u8, params, '&');

        while (keyvals.next()) |param| {
            var p = mem.splitScalar(u8, param, '=');
            const name = p.next().?;
            const value = p.next().?;
            try self.params.add(name, try u.urlDecode(self.allocator, value));

            try self.route.writer().print("/:{s}", .{name});
        }
    }

    //get request headers
    while (lines.next()) |item| {
        if (item.len == 0) break;
        var header = mem.splitScalar(u8, item, ':');
        const name = @constCast(header.next()) orelse return error.InvalidHeader;
        const value = header.next().?;
        u.lowerStringInPlace(name);

        try self.headers.add(name, value[1..]);
    }

    //Get Request Body
    if (self.method == .post or self.method == .put) {
        if (self.headers.get("content-length")) |content_length_str| {
            const content_length = try std.fmt.parseInt(usize, content_length_str, 10);
            if (lines.next()) |body| {
                try self.body.appendSlice(body[0..content_length]);
            }
        } else {
            var chunks = Chunks.init(self.allocator, self.socket);
            const body = try chunks.readChunks();
            if (body) |b| {
                try self.body.appendSlice(b);
            }
        }
    }
}

pub fn parse(self: *Request, buff: []const u8) !void {
    var lines = mem.splitSequence(u8, buff, "\r\n");

    //get first line of request
    const first_line = lines.next() orelse return error.InvalidRequest;

    var flit = std.mem.splitScalar(u8, first_line, ' ');

    if (flit.next()) |method| {
        self.method = try Method.fromString(method);
    } else {
        std.log.err("No Method in: {s}", .{buff});
    }

    if (flit.next()) |path| {
        if (mem.eql(u8, path, "/")) {
            self.path = try self.allocator.dupe(u8, "/index.html");
        } else {
            self.path = try self.allocator.dupe(u8, path);
        }
    } else {
        std.log.err("No Path in: {s}", .{buff});
    }

    if (flit.next()) |version| {
        self.version = try Version.fromString(version);
    } else {
        std.log.err("No Version in: {s}", .{buff});
    }

    //get request parameters and url route for api patameters
    var path_iter = mem.splitScalar(u8, self.path, '?');
    //skip contents before '?'
    if (path_iter.next()) |segs| {
        if (mem.startsWith(u8, segs, "/api")) {
            var seg_iter = std.mem.splitSequence(u8, segs, "/");
            _ = seg_iter.next().?;
            _ = seg_iter.next().?;
            const resource = seg_iter.next().?;
            try self.route.writer().print("/{s}", .{resource});
        }
    }

    if (path_iter.next()) |params| {
        var keyvals = mem.splitScalar(u8, params, '&');

        while (keyvals.next()) |param| {
            var p = mem.splitScalar(u8, param, '=');
            const name = p.next().?;
            const value = p.next().?;
            try self.params.add(name, try u.urlDecode(self.allocator, value));

            try self.route.writer().print("/:{s}", .{name});
        }
    }

    //get request headers
    while (lines.next()) |item| {
        if (item.len == 0) break;
        var header = mem.splitScalar(u8, item, ':');
        const name = @constCast(header.next()) orelse return error.InvalidHeader;
        const value = header.next().?;
        u.lowerStringInPlace(name);

        try self.headers.add(name, value[1..]);
    }

    //Get Request Body
    if (self.method == .post or self.method == .put) {
        if (self.headers.get("content-length")) |content_length_str| {
            const content_length = try std.fmt.parseInt(usize, content_length_str, 10);
            if (lines.next()) |body| {
                try self.body.appendSlice(body[0..content_length]);
            }
        } else {
            var chunks = Chunks.init(self.allocator, self.socket);
            const body = try chunks.readChunks();
            if (body) |b| {
                try self.body.appendSlice(b);
            }
        }
    }
}

pub fn toBytes(self: *Request) ![]const u8 {
    
    var buffer = std.ArrayList(u8).init(self.allocator);
    
    try buffer.writer().print("{s} {s} {s}\r\n", .{ self.method.toString(), self.path, self.version.toString() });

    if (self.body.items.len > 5000) {
        try self.setHeader("Transfer-Encoding", "chunked");
    } else {
        try self.setHeader("Content-Length", try std.fmt.allocPrint(self.allocator, "{}", .{self.body.items.len}));
    }

    // Write headers
    for (self.headers.list.items, 0..) |item, i| {
        _ = i;
        try buffer.writer().print("{s}: {s}\r\n", .{ item.name, item.value });
    }

    _ = try buffer.write("\r\n");

        // Write body if present
        if (self.body.items.len > 0) {
            _ = try buffer.writer().write(self.body.items);
        } else {
            _ = try buffer.writer().write("\r\n");
        }
    return buffer.items;
}

pub fn send(self: *Request) !void {
    var buffer = std.ArrayList(u8).init(self.allocator);
    
    try buffer.writer().print("{s} {s} {s}\r\n", .{ self.method.toString(), self.path, self.version.toString() });

    if (self.body.items.len > 5000) {
        try self.setHeader("Transfer-Encoding", "chunked");
    } else {
        try self.setHeader("Content-Length", try std.fmt.allocPrint(self.allocator, "{}", .{self.body.items.len}));
    }

    // Write headers
    for (self.headers.list.items, 0..) |item, i| {
        _ = i;
        try buffer.writer().print("{s}: {s}\r\n", .{ item.name, item.value });
    }

    _ = try buffer.write("\r\n");

    if (self.body.items.len > 5000) {
        try coro.io.single(.send, .{ .socket = self.client, .buffer = buffer.items });
        const chunk_size = 5000;
        var start: usize = 0;
        while (start < self.body.items.len) {
            const end = @min(start + chunk_size, self.body.items.len);
            const chunk = try self.allocator.alloc(u8, end - start);
            @memcpy(chunk, self.body.items[start..end]);

            try Chunks.writeChunk(self.allocator, self.socket, chunk);
            start = end;
        }
        try Chunks.writeFinalChunk(self.socket);
    } else {
        // Write body if present
        if (self.body.items.len > 0) {
            _ = try buffer.writer().write(self.body.items);
        } else {
            _ = try buffer.writer().write("\r\n");
        }
        try coro.io.single(.send, .{ .socket = self.client, .buffer = buffer.items });
    }
}

pub fn deinit(self: *Request) void {
    self.headers.deinit();
    self.params.deinit();
    self.body.deinit();
    self.route.deinit();
}
