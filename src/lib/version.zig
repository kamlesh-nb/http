const std = @import("std");
const meta = std.meta;
const ascii = std.ascii;

pub const Version = enum {
    Http09,
    Http10,
    Http11,
    H2,
    H3,

    pub fn fromString(str: []const u8) !Version {
        if (std.ascii.eqlIgnoreCase(str, "HTTP/0.9")) {
            return .Http09;
        } else if (std.ascii.eqlIgnoreCase(str, "HTTP/1.0")) {
            return .Http10;
        } else if (std.ascii.eqlIgnoreCase(str, "HTTP/1.1")) {
            return .Http11;
        } else if (std.ascii.eqlIgnoreCase(str, "HTTP/2.0")) {
            return .H2;
        } else if (std.ascii.eqlIgnoreCase(str, "HTTP/3.0")) {
            return .H3;
        } else {
            return error.InvalidStatus;
        }
    }
    pub fn toString(self: Version) []const u8 {
        switch (self) {
            .Http09 => return "HTTP/0.9",
            .Http10 => return "HTTP/1.0",
            .Http11 => return "HTTP/1.1",
            .H2 => return "HTTP/2.0",
            .H3 => return "HTTP/3.0",
        }
    }
};
