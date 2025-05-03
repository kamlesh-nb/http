const std = @import("std");
const mem = std.mem;
const aio = @import("aio");
const coro = @import("coro");

const Chunks = @import("./chunks.zig").Chunks;

const Mime = @import("./mime.zig").Mime;
const Pairs = @import("./pairs.zig").Pairs;
const Status = @import("./status.zig").Status;
const Version = @import("./version.zig").Version;
// const Buffer = @import("./buffer.zig");

pub const Response = @This();

allocator: mem.Allocator,
client: std.posix.socket_t = undefined,
status: Status = undefined,
version: Version = undefined,
headers: Pairs,
body: std.ArrayList(u8),
written: bool = false,

pub fn new(allocator: mem.Allocator, socket: std.posix.socket_t) !Response {
    return Response{
        .client = socket,
        .allocator = allocator,
        .headers = try Pairs.init(allocator),
        .body = std.ArrayList(u8).init(allocator),
    };
}

pub fn setHeader(self: *Response, name: []const u8, value: []const u8) !void {
    try self.headers.add(name, value);
}

pub fn write(self: *Response, data: []const u8) !void {
    _ = try self.body.appendSlice(data);
}

pub fn json(self: *Response, data: anytype) !void {
    const json_str = try std.json.stringifyAlloc(self.allocator, data, .{});
    defer self.allocator.free(json_str);
    try self.write(json_str);

    try self.setHeader("Content-Type", "application/json");
    try self.setHeader("Connection", "Close");
    self.status = Status.ok;
}

pub fn sendError(self: *Response) !void {
    try self.setHeader("Content-Type", "text/plain");
    try self.setHeader("Connection", "Close");
    switch (self.status) {
        .not_found => {
            _ = try self.body.appendSlice("Not Found");
        },
        .forbidden => {
            _ = try self.body.appendSlice("Forbiden");
        },
        .internal_server_error => {
            _ = try self.body.appendSlice("Internal Server Error");
        },
        else => {},
    }
}

pub fn read(self: *Response) !void {
    const buf = try self.allocator.alloc(u8, 4096);
    var len: usize = 0;

    try coro.io.single(.recv, .{ .socket = self.socket, .buffer = buf, .out_read = &len });

    var lines = mem.splitSequence(u8, buf, "\r\n");

    //Get status line of response
    const first_line = lines.next() orelse return error.InvalidResponse;

    var flit = std.mem.splitScalar(u8, first_line, ' ');

    if (flit.next()) |version| {
        self.version = try Version.fromString(version);
    } else {
        std.log.err("No Method in: {s}", .{buf});
    }

    if (flit.next()) |status| {
        self.status = @enumFromInt(try std.fmt.parseInt(u16, status, 10));
    } else {
        std.log.err("No Status in: {s}", .{buf});
    }
    //ignore status phrase
    _ = flit.next();

    //get response headers
    while (lines.next()) |item| {
        if (item.len == 0) break;
        var header = mem.splitScalar(u8, item, ':');
        const name = header.next().?;
        const value = header.next().?;
        try self.headers.add(name, value[1..]);
    }

    if (self.headers.get("Content-Length")) |content_length_str| {
        const content_length = try std.fmt.parseInt(usize, content_length_str, 10);
        if (lines.next()) |body| {
            try self.body.appendSlice(body[0..content_length]);
        }
    } else {
        var chunks = Chunks.init(self.allocator, self.client);
        const body = try chunks.readChunks();
        if (body) |b| {
            try self.body.appendSlice(b);
        }
    }
}

pub fn parse(self: *Response, buf: []const u8) !void {
    var lines = mem.splitSequence(u8, buf, "\r\n");

    //Get status line of response
    const first_line = lines.next() orelse return error.InvalidResponse;

    var flit = std.mem.splitScalar(u8, first_line, ' ');

    if (flit.next()) |version| {
        self.version = try Version.fromString(version);
    } else {
        std.log.err("No Method in: {s}", .{buf});
    }

    if (flit.next()) |status| {
        self.status = @enumFromInt(try std.fmt.parseInt(u16, status, 10));
    } else {
        std.log.err("No Status in: {s}", .{buf});
    }
    //ignore status phrase
    _ = flit.next();

    //get response headers
    while (lines.next()) |item| {
        if (item.len == 0) break;
        var header = mem.splitScalar(u8, item, ':');
        const name = header.next().?;
        const value = header.next().?;
        try self.headers.add(name, value[1..]);
    }

    if (self.headers.get("Content-Length")) |content_length_str| {
        const content_length = try std.fmt.parseInt(usize, content_length_str, 10);
        if (lines.next()) |body| {
            try self.body.appendSlice(body[0..content_length]);
        }
    } else {
        var chunks = Chunks.init(self.allocator, self.client);
        const body = try chunks.readChunks();
        if (body) |b| {
            try self.body.appendSlice(b);
        }
    }
}

pub fn send(self: *Response) !void {
    if (self.written) return;
    self.written = true;

    if (self.status != .ok) {
        try self.sendError();
    }
    var buffer = std.ArrayList(u8).init(self.allocator);
    try buffer.writer().print("HTTP/1.1 {} {s}\r\n", .{
        @intFromEnum(self.status),
        self.status.toString(),
    });

    //transfer chunked
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

    _ = try buffer.writer().write("\r\n");

    if (self.body.items.len > 5000) {
        try coro.io.single(.send, .{ .socket = self.client, .buffer = buffer.items });

        const chunk_size = 5000;
        var start: usize = 0;
        while (start < self.body.items.len) {
            const end = @min(start + chunk_size, self.body.items.len);
            const chunk = try self.allocator.alloc(u8, end - start);
            @memcpy(chunk, self.body.items[start..end]);

            try Chunks.writeChunk(self.allocator, self.client, chunk);
            start = end;
        }
        try Chunks.writeFinalChunk(self.client);
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
