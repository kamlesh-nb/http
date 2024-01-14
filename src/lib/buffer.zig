const std = @import("std");
const assert = std.debug.assert;

const builtin = @import("builtin");

const Buffer = @This();

buffer: ?[]u8,
allocator: std.mem.Allocator,
size: usize,

pub const Error = error{
    OutOfMemory,
    InvalidRange,
};

pub fn init(allocator: std.mem.Allocator) Buffer {
    return .{
        .buffer = null,
        .allocator = allocator,
        .size = 0,
    };
}

pub fn create(allocator: std.mem.Allocator, contents: []const u8) Error!Buffer {
    var string = init(allocator);

    try string.concat(contents);

    return string;
}

/// Allocates space for the internal buffer
pub fn allocate(self: *Buffer, bytes: usize) Error!void {
    if (self.buffer) |buffer| {
        if (bytes < self.size) self.size = bytes; // Clamp size to capacity
        self.buffer = self.allocator.realloc(buffer, bytes) catch {
            return Error.OutOfMemory;
        };
    } else {
        self.buffer = self.allocator.alloc(u8, bytes) catch {
            return Error.OutOfMemory;
        };
    }
}

 

/// Appends a character onto the end of the String
pub fn concat(self: *Buffer, char: []const u8) Error!void {
    try self.insert(char, self.len());
}

/// Inserts a string literal into the String at an index
pub fn insert(self: *Buffer, literal: []const u8, index: usize) Error!void {
    // Make sure buffer has enough space
    if (self.buffer) |buffer| {
        if (self.size + literal.len > buffer.len) {
            try self.allocate((self.size + literal.len) * 2);
        }
    } else {
        try self.allocate((literal.len) * 2);
    }

    const buffer = self.buffer.?;

    // If the index is >= len, then simply push to the end.
    // If not, then copy contents over and insert literal.
    if (index == self.len()) {
        var i: usize = 0;
        while (i < literal.len) : (i += 1) {
            buffer[self.size + i] = literal[i];
        }
    } else {
        if (Buffer.getIndex(buffer, index, true)) |k| {
            // Move existing contents over
            var i: usize = buffer.len - 1;
            while (i >= k) : (i -= 1) {
                if (i + literal.len < buffer.len) {
                    buffer[i + literal.len] = buffer[i];
                }

                if (i == 0) break;
            }

            i = 0;
            while (i < literal.len) : (i += 1) {
                buffer[index + i] = literal[i];
            }
        }
    }

    self.size += literal.len;
}

/// Returns amount of characters in the String
pub fn len(self: Buffer) usize {
    if (self.buffer) |buffer| {
        var length: usize = 0;
        var i: usize = 0;

        while (i < self.size) {
            i += Buffer.getUTF8Size(buffer[i]);
            length += 1;
        }

        return length;
    } else {
        return 0;
    }
}

/// Returns the String as a string literal
pub fn str(self: Buffer) []const u8 {
    if (self.buffer) |buffer| return buffer[0..self.size];
    return "";
}

/// Returns an owned slice of this string
pub fn toOwned(self: Buffer) Error!?[]u8 {
    if (self.buffer != null) {
        const string = self.str();
        if (self.allocator.alloc(u8, string.len)) |newStr| {
            @memcpy(newStr, string);
            return newStr;
        } else |_| {
            return Error.OutOfMemory;
        }
    }

    return null;
}

/// Finds the first occurrence of the string literal
pub fn find(self: Buffer, literal: []const u8) ?usize {
    if (self.buffer) |buffer| {
        const index = std.mem.indexOf(u8, buffer[0..self.size], literal);
        if (index) |i| {
            return Buffer.getIndex(buffer, i, false);
        }
    }

    return null;
}

/// Splits the String into a slice, based on a delimiter and an index
pub fn split(self: *const Buffer, delimiters: []const u8, index: usize) ?[]const u8 {
    if (self.buffer) |buffer| {
        var i: usize = 0;
        var block: usize = 0;
        var start: usize = 0;

        while (i < self.size) {
            const size = Buffer.getUTF8Size(buffer[i]);
            if (size == delimiters.len) {
                if (std.mem.eql(u8, delimiters, buffer[i..(i + size)])) {
                    if (block == index) return buffer[start..i];
                    start = i + size;
                    block += 1;
                }
            }

            i += size;
        }

        if (i >= self.size - 1 and block == index) {
            return buffer[start..self.size];
        }
    }

    return null;
}

/// Clears the contents of the String but leaves the capacity
pub fn clear(self: *Buffer) void {
    if (self.buffer) |buffer| {
        for (buffer) |*ch| ch.* = 0;
        self.size = 0;
    }
}

/// Splits the String into a new string, based on delimiters and an index
/// The user of this function is in charge of the memory of the new String.
pub fn splitToBuffer(self: *const Buffer, delimiters: []const u8, index: usize) Error!?Buffer {
    if (self.split(delimiters, index)) |block| {
        var string = Buffer.init(self.allocator);
        try string.concat(block);
        return string;
    }

    return null;
}

/// Creates a String from a given range
/// User is responsible for managing the new String
pub fn substr(self: Buffer, start: usize, end: usize) Error!Buffer {
    var result = Buffer.init(self.allocator);

    if (self.buffer) |buffer| {
        if (Buffer.getIndex(buffer, start, true)) |rStart| {
            if (Buffer.getIndex(buffer, end, true)) |rEnd| {
                if (rEnd < rStart or rEnd > self.size)
                    return Error.InvalidRange;
                try result.concat(buffer[rStart..rEnd]);
            }
        }
    }

    return result;
}

/// Returns the real index of a unicode string literal
fn getIndex(unicode: []const u8, index: usize, real: bool) ?usize {
    var i: usize = 0;
    var j: usize = 0;
    while (i < unicode.len) {
        if (real) {
            if (j == index) return i;
        } else {
            if (i == index) return j;
        }
        i += Buffer.getUTF8Size(unicode[i]);
        j += 1;
    }

    return null;
}

/// Returns the UTF-8 character's size
inline fn getUTF8Size(char: u8) u3 {
    return std.unicode.utf8ByteSequenceLength(char) catch {
        return 1;
    };
}

/// Deallocates the internal buffer
pub fn deinit(self: *Buffer) void {
    if (self.buffer) |buffer| self.allocator.free(buffer);
}
