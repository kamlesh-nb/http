const std = @import("std");
const posix = std.posix;

const aio = @import("aio");
const coro = @import("coro");

pub const Chunks = struct {
    allocator: std.mem.Allocator,
    socket: posix.socket_t,
    state: State = .chunk_size,
    remaining_chunk_bytes: usize = 0,
    buffer: std.ArrayList(u8),

    const State = enum {
        chunk_size,
        chunk_data,
        chunk_end,
        trailer,
        complete,
    };

    pub fn init(allocator: std.mem.Allocator, socket: posix.socket_t) Chunks {
        return .{
            .allocator = allocator,
            .socket = socket,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Chunks) void {
        self.buffer.deinit();
    }

    /// Reads from socket until the delimiter is found
    fn readUntilDelimiter(self: *Chunks, delimiter: u8) ![]const u8 {
        self.buffer.clearRetainingCapacity();

        while (true) {
            var byte: [1]u8 = undefined;
            var len: usize = 0;
            try coro.io.single(.recv, .{ .socket = self.socket, .buffer = &byte, .out_read = &len });

            if (len == 0) return error.ConnectionClosed;

            try self.buffer.append(byte[0]);

            if (byte[0] == delimiter) {
                return self.buffer.items;
            }
        }
    }

    /// Reads exactly `count` bytes from socket
    fn readExact(self: *Chunks, buf: []u8) !void {
        var total_read: usize = 0;
        while (total_read < buf.len) {
            var len: usize = 0;

            try coro.io.single(.recv, .{ .socket = self.socket, .buffer = buf, .out_read = &len });

            if (len == 0) return error.ConnectionClosed;
            total_read += len;
        }
    }

    /// Read Chunks the next chunk of data
    pub fn readChunks(self: *Chunks) !?[]const u8 {
        var output_buffer = std.ArrayList(u8).init(self.allocator);
        defer output_buffer.deinit();

        while (true) {
            switch (self.state) {
                .chunk_size => {
                    const size_line = try self.readUntilDelimiter('\n');
                    const size_str = std.mem.trim(u8, size_line, " \r\n");

                    if (size_str.len == 0) return error.InvalidChunkSize;
                    self.remaining_chunk_bytes = std.fmt.parseInt(usize, size_str, 16) catch |err| {
                        return err;
                    };

                    if (self.remaining_chunk_bytes == 0) {
                        self.state = .trailer;
                        continue;
                    }

                    self.state = .chunk_data;
                },
                .chunk_data => {
                    try output_buffer.ensureTotalCapacity(self.remaining_chunk_bytes);
                    const start_len = output_buffer.items.len;
                    output_buffer.items.len += self.remaining_chunk_bytes;

                    try self.readExact(output_buffer.items[start_len..]);
                    self.remaining_chunk_bytes = 0;
                    self.state = .chunk_end;

                    // Return the complete chunk
                    break;
                },
                .chunk_end => {
                    var crlf: [2]u8 = undefined;
                    try self.readExact(&crlf);
                    if (!std.mem.eql(u8, &crlf, "\r\n")) {
                        return error.InvalidChunkEnd;
                    }
                    self.state = .chunk_size;

                    // If we have data, return it
                    if (output_buffer.items.len > 0) {
                        break;
                    }
                },
                .trailer => {
                    // Skip trailer headers
                    while (true) {
                        const line = try self.readUntilDelimiter('\n');
                        if (std.mem.trim(u8, line, " \r\n").len == 0) break;
                    }
                    self.state = .complete;
                    return null;
                },
                .complete => return null,
            }
        }

        return try output_buffer.toOwnedSlice();
    }

    /// Helper to write chunked data to socket
    pub fn writeChunk(allocator: std.mem.Allocator, socket: posix.socket_t, data: []const u8) !void {
        // Write chunk size
        const buf = try std.fmt.allocPrint(allocator, "{x}\r\n{s}\r\n", .{ data.len, data });
        try coro.io.single(.send, .{ .socket = socket, .buffer = buf });
    }

    /// Write final chunk (zero-length) to signal end
    pub fn writeFinalChunk(socket: posix.socket_t) !void {
        try coro.io.single(.send, .{ .socket = socket, .buffer = "0\r\n\r\n" });
    }
};
