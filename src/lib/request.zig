const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = @import("method.zig").Method;
const Version = @import("version.zig").Version;
const Body = @import("body.zig");
const Buffer = @import("buffer.zig").Buffer;
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
        state: Util.ParseState = .first_line,
        event: Util.Event = .status,
        encoding: Util.TransferEncoding = .unknown,
        has_chunked_trailer: bool = false,
        read_buffer: [32768]u8 = undefined,
        read_needed: usize = 0,
        read_current: usize = 0,
        body_len: usize = 0,
        has_body: bool = false,
        trailer_state: bool = false,
        done: bool = false,
        headers_done: bool = false,
        body_done: bool = false,
        temp_uri: []u8 = undefined,

        fn read_first_line(self: *Parser, reader: anytype) !void {
            var first_line: [1024]u8 = undefined;
            const line = try Util.readUntilEndOfLine(reader, &first_line);
            const index_separator = std.mem.indexOf(u8, line, " ") orelse 0;
            if (index_separator == 0)
                return;
            const method = line[0..index_separator];
            const uri = line[index_separator + 1 ..];
            const index_uri = std.mem.indexOf(u8, uri, " ") orelse 0;
            if (index_uri == 0)
                return;
            self.temp_uri = uri[0..index_uri];
            const version = uri[index_uri + 1 ..];
            if (std.ascii.eqlIgnoreCase(method, "GET")) {
                self.request.parts.method = Method.get;
            } else if (std.ascii.eqlIgnoreCase(method, "POST")) {
                self.request.parts.method = Method.post;
            } else if (std.ascii.eqlIgnoreCase(method, "PUT")) {
                self.request.parts.method = Method.put;
            } else if (std.ascii.eqlIgnoreCase(method, "DELETE")) {
                self.request.parts.method = Method.delete;
            } else if (std.ascii.eqlIgnoreCase(method, "HEAD")) {
                self.request.parts.method = Method.head;
            } else if (std.ascii.eqlIgnoreCase(method, "OPTIONS")) {
                self.request.parts.method = Method.options;
            } else if (std.ascii.eqlIgnoreCase(method, "PATCH")) {
                self.request.parts.method = Method.patch;
            } else {
                return error.InvalidMethod;
            }
            if (std.ascii.eqlIgnoreCase(version, "HTTP/1.0")) {
                self.request.parts.version = Version.Http10;
            } else if (std.ascii.eqlIgnoreCase(version, "HTTP/1.1")) {
                self.request.parts.version = Version.Http11;
            } else if (std.ascii.eqlIgnoreCase(version, "HTTP/2.0")) {
                self.request.parts.version = Version.H2;
            } else {
                return error.InvalidVersion;
            }

            // self.request.parts.uri = try std.Uri.parse(path);
            // if (self.request.parts.uri.scheme.len == 0) {
            //     return error.InvalidUri;
            // }
            // if (!std.mem.eql(u8, self.request.parts.uri.scheme, "http") and !std.mem.eql(u8, self.request.parts.uri.scheme, "https")) {
            //     return error.InvalidUri;
            // }
            // if (self.request.parts.uri.host == null) {
            //     return error.InvalidUri;
            // }
            self.state = .header;
        }

        fn read_headers(self: *Parser, reader: anytype) !void {
            var header: [1024]u8 = undefined;
            const line = try Util.readUntilEndOfLine(reader, &header);
            if (line.len == 0) {
                if (self.trailer_state) {
                    self.encoding = .unknown;
                    self.done = true;
                } else {
                    self.state = .body;
                    self.headers_done = true;
                }
            }

            const index_separator = std.mem.indexOf(u8, line, ":") orelse 0;
            if (index_separator == 0)
                return;

            const name = line[0..index_separator];
            const value = std.mem.trim(u8, line[index_separator + 1 ..], &[_]u8{ ' ', '\t' });

            if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                if (self.encoding != .unknown) return error.InvalidEncodingHeader;

                self.encoding = .content_length;
                const content_len = try std.fmt.parseInt(u16, value[0..], 16);
                if (content_len == 0) {
                    self.has_body = false;
                } else {
                    self.has_body = true;
                }

                self.read_needed = std.fmt.parseUnsigned(usize, value, 10) catch return error.InvalidEncodingHeader;
            } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
                if (self.encoding != .unknown) return error.InvalidEncodingHeader;

                // We can only decode chunked messages, not compressed messages
                if (std.ascii.indexOfIgnoreCase(value, "chunked") orelse 1 == 0) {
                    self.encoding = .chunked;
                    self.has_body = true;
                }
            } else if (std.ascii.eqlIgnoreCase(name, "trailer")) {
                self.has_chunked_trailer = true;
            }
            self.request.parts.headers.add(name, value);
        }

        fn read_body(self: *Parser, reader: anytype) !void {
            if (!self.has_body) {
                self.done = true;
                return;
            }
            switch (self.encoding) {
                .unknown => {
                    self.done = true;
                },
                .content_length => {
                    const left = @min(self.read_needed - self.read_current, self.read_buffer.len);
                    const nread = try reader.read(self.read_buffer[0..left]);

                    self.read_current += nread;

                    // Is it even possible for read_current to be > read_needed?
                    if (self.read_current >= self.read_needed) {
                        self.encoding = .unknown;
                    }
                    _ = try self.request.body.buffer.write(self.read_buffer[0..nread]);
                },
                .chunked => {
                    if (self.read_needed == 0) {
                        const line = try Util.readUntilEndOfLine(reader, &self.read_buffer);
                        const chunk_len = std.fmt.parseUnsigned(usize, line, 16) catch return error.InvalidChunkedPayload;

                        if (chunk_len == 0) {
                            if (self.has_chunked_trailer) {
                                self.state = .header;
                                self.trailer_state = true;
                            } else {
                                self.encoding = .unknown;
                                self.done = true;
                                return;
                            }
                        } else {
                            self.read_needed = chunk_len;
                            self.read_current = 0;
                        }
                    }

                    const left = @min(self.read_needed - self.read_current, self.read_buffer.len);
                    const nread = try reader.read(self.read_buffer[0..left]);

                    self.read_current += nread;

                    // Is it even possible for read_current to be > read_needed?
                    if (self.read_current >= self.read_needed) {
                        var crlf: [2]u8 = undefined;
                        const lfread = try reader.readAll(&crlf);

                        if (lfread < 2) return error.EndOfStream;
                        if (crlf[0] != '\r' or crlf[1] != '\n') return error.InvalidChunkedPayload;

                        self.read_needed = 0;
                    }

                    _ = try self.request.body.buffer.write(self.read_buffer[0..nread]);
                },
            }
        }

        fn next(self: *Parser, reader: anytype) !void {
            //
            try read_first_line(self, reader);
            while (!self.headers_done) {
                if (self.done)
                    break;
                try read_headers(self, reader);
            }

            while (!self.done) {
                try read_body(self, reader);
            }
        }

        pub fn parse(self: *Parser, reader: anytype) !void {
            try next(self, reader);
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

        pub fn send(self: *Sender, writer: anytype) !usize {
            var buffer = Buffer.init(self.request.allocator);
            defer buffer.deinit();
            _ = try buffer.writer().print("{s} ", .{self.request.parts.method.toString()});
            _ = try buffer.writer().print("{s} {s}\r\n", .{ self.request.parts.uri.path, self.request.parts.version.toString() });
            var it = self.request.parts.headers.iterator();
            while (it.next()) |header| {
                _ = try buffer.writer().print("{s}: {s}\r\n", .{ header.name, header.value });
            }

            _ = try buffer.write("\r\n");

            if (self.request.parts.method.shouldHaveBody()) {
                _ = try buffer.write(self.request.body.buffer.str());
            }

            writer.writeAll(buffer.str()) catch |err| {
                std.log.err("Error: {?}", .{err});
            };

            return buffer.size;
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
    _ = try request.body.buffer.write("{ \"name\":  \"oooop\", \"age\": 54 }");
    defer request.deinit();
    request.parts.headers.add("name", "loooop");

    const person = try request.body.get(std.testing.allocator, Person);
    std.debug.print("name: {s} & age: {d}\n", .{ person.name, person.age });
    std.debug.print("\n uri: {s}, method: {s}, version: {s}\n", .{ request.parts.uri.scheme, request.parts.method.toString(), request.parts.version.toString() });
    std.debug.print("\n name: {s} \n", .{request.parts.headers.get("name").?});
}
