const std = @import("std");
const Allocator = std.mem.Allocator;
const Status = @import("status.zig").Status;
const Body = @import("body.zig");
const Version = @import("version.zig").Version;
const Headers = @import("header.zig");
const Util = @import("util.zig");
const Errors = @import("errors.zig");
const Buffer = @import("buffer").Buffer;
const Response = @This();

pub const Parts = struct {
    status: Status = undefined,
    headers: Headers = undefined,
    version: Version = undefined,
};

parts: Parts,
body: Body,
allocator: Allocator,

pub fn new(allocator: Allocator, status: Status, version: Version) !Response {
    return Response{
        .parts = Parts{
            .status = status,
            .version = version,
            .headers = try Headers.init(allocator, 1024),
        },
        .body = Body{ .buffer = Buffer.init(allocator) },
        .allocator = allocator,
    };
}

pub fn init(allocator: Allocator) !Response {
    return Response{
        .parts = Parts{
            .headers = try Headers.init(allocator, 1024),
        },
        .body = Body{ .buffer = Buffer.init(allocator) },
        .allocator = allocator,
    };
}

pub fn deinit(self: *Response) void {
    self.parts.headers.deinit(self.allocator);
    self.body.buffer.deinit();
}

pub usingnamespace struct {
    pub const Parser = struct {
        response: *Response,
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

        fn read_status(self: *Parser, reader: anytype) !void {
            var status: [1024]u8 = undefined;
            const line = try Util.readUntilEndOfLine(reader, &status);
            if (line.len == 0)
                self.event = .skip; // RFC 7230 Section 3.5
            if (line.len < 13) return error.InvalidStatusLine;

            if (line[8] != ' ') return error.InvalidStatusLine;
            if (line[12] != ' ') return error.InvalidStatusLine;

            self.response.parts.version = try Version.fromString(line[0..8]);
            self.response.parts.status = try Status.fromString(line[9..12]);
            self.state = .header;
        }

        fn read_headers(self: *Parser, reader: anytype) !void {
            var header: [1024]u8 = undefined;
            const line = try Util.readUntilEndOfLine(reader, &header);
            if (line.len == 0) {
                if (self.trailer_state) {
                    self.encoding = .unknown;
                    self.done = true;
                    // self.event = .end;
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
            self.response.parts.headers.add(name, value);
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
                    _ = try self.response.body.buffer.write(self.read_buffer[0..nread]);
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

                    _ = try self.response.body.buffer.write(self.read_buffer[0..nread]);
                },
            }
        }

        fn next(self: *Parser, reader: anytype) !void {
            //
            try read_status(self, reader);
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

    pub fn parser(res: *Response) Parser {
        return Parser{
            .response = res,
            .state = .first_line,
        };
    }

    pub const Writer = struct {
        response: *Response,
        status: i32,

        pub fn write(self: Writer, comptime reader: type) i32 {
            _ = reader;
            _ = self;
        }
    };

    pub fn writer(res: *Response) Writer {
        return Writer{
            .response = res,
            .status = 0,
        };
    }
};

test "response" {
    const Person = struct {
        name: []const u8,
        age: i32,
    };

    var response = try Response.new(std.testing.allocator, .ok, .Http11);
    try response.body.set("{ \"name\":  \"oooop\", \"age\": 54 }");
    defer response.deinit(std.testing.allocator);
    response.parts.headers.add("name", "oooop");

    const person = try response.body.get(std.testing.allocator, Person);
    std.debug.print("Person: {?}\n", .{person});
    std.debug.print("\n status: {s} \n", .{response.parts.status.toString()});
    std.debug.print("\n version: {s} \n", .{response.parts.version.toString()});
    std.debug.print("\n name: {s} \n", .{response.parts.headers.get("name").?});
}
