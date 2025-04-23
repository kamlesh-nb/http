const std = @import("std");

pub fn urlDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    var i: usize = 0;

    while (i < input.len) {
        if (input[i] == '%') {
            if (i + 2 >= input.len) return error.InvalidEncoding;
            const hex = input[i + 1 .. i + 3];
            const value = try std.fmt.parseInt(u8, hex, 16);
            try list.append(value);
            i += 3;
        } else if (input[i] == '+') {
            try list.append(' ');
            i += 1;
        } else {
            try list.append(input[i]);
            i += 1;
        }
    }

    return list.toOwnedSlice();
}

pub fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);

    for (input) |char| {
        switch (char) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~' => try list.append(char),
            ' ' => try list.append("%20"),
            else => {
                var buf: [3]u8 = undefined;
                _ = try std.fmt.bufPrint(&buf, "%{X:0>2}", .{char});
                try list.append('%');
                try list.append(buf[0]);
                try list.append(buf[1]);
            },
        }
    }

    return list.toOwnedSlice();
}

pub fn lowerStringInPlace(str: []u8) void {
    for (str) |*c| {
        c.* = std.ascii.toLower(c.*);
    }
}
