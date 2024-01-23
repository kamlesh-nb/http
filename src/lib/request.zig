const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = @import("method.zig").Method;
const Version = @import("version.zig").Version;
const Body = @import("body.zig");
const Buffer = @import("buffer").Buffer;
const Headers = @import("header.zig");
const Util = @import("util.zig");

const Request = @This();

pub const Parts = struct {
    method: Method = undefined,
    uri: std.Uri = undefined,
    headers: Headers = undefined,
    version: Version = undefined,
};

parts: Parts,
body: Body,
allocator: Allocator,

pub fn new(allocator: Allocator, uri: std.Uri, method: Method, version: Version) !Request {
   return Request{
        .parts = Parts{
            .uri = uri,
            .method = method,
            .version = version,
            .headers = try Headers.init(allocator, 1024),
        },
        .body = Body{ .buffer = Buffer.init(allocator) },
        .allocator = allocator,
    };
}

pub fn init(allocator: Allocator) !Request {
    return Request{
        .parts = Parts{
            .headers = try Headers.init(allocator, 1024),
        },
        .body = Body{ .buffer = Buffer.init(allocator) },
        .allocator = allocator,
    };
}

pub fn deinit(self: *Request) void {
     self.parts.headers.deinit(self.allocator);
    self.body.buffer.deinit();
}

pub usingnamespace struct {
    pub const Parser = struct {
        request: *Request,
        state: Util.ParseState,

        pub fn parse(self: *Parser, reader: anytype) Request {
            _ = reader;
            return self.request;
        }
    };

    pub fn parser(req: *Request) Parser {
        return Parser{
            .request = req,
            .state = .first_line,
        };
    }

    pub const Sender = struct {
        request: *Request,
        status: usize,

        fn toBytes(self: *Sender) []const u8 {
            var buffer = try Buffer.init(self.request.allocator);
            defer buffer.deinit();
            buffer.writer().print("{s} ", .{self.request.parts.method.toString()});
            buffer.writer().print("{s} {s}\r\n", .{self.request.parts.uri.path, self.request.parts.version.toString()});
            var it = self.request.parts.headers.iterator();
            while (it.next()) |header| {
                 buffer.writer().print("{s}: {s}\r\n", .{header.name, header.value});
            }

            try buffer.write("\r\n");

            if (self.request.parts.method.shouldHaveBody()) {
                try buffer.write(self.request.body.buffer.str());
            }
            return buffer.str();
        }

        pub fn send(self: *Sender, writer: anytype) !usize {
            const bytes = try self.toBytes();

            if (bytes) |data| {
                defer self.request.allocator.free(data);
                writer.writeAll(data) catch |err| {
                    std.log.err("Error: {?}", .{err});
                };
                return data.len;
            } else {
                return 0;
            }
        }
    };

    pub fn sender(req: *Request) Sender {
        return Sender{
            .request = req,
            .status = 0,
        };
    }
};

test "request" {
    const Person = struct {
        name: []const u8,
        age: i32,
    };

    const uri = try std.Uri.parse("https:://www.google.com");
    var request = try Request.new(std.testing.allocator, uri, .get, .Http11);
    try request.body.buffer.write("{ \"name\":  \"oooop\", \"age\": 54 }");
    defer request.deinit(std.testing.allocator);
    request.parts.headers.add("name", "oooop");

    const person = try request.body.get(std.testing.allocator, Person);
    std.debug.print("name: {s} & age: {d}\n", .{ person.name, person.age });
    std.debug.print("\n uri: {s}, method: {s}, version: {s}\n", .{ request.parts.uri.scheme, request.parts.method.toString(), request.parts.version.toString() });
    std.debug.print("\n name: {s} \n", .{request.parts.headers.get("name").?});
}

