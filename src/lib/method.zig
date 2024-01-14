const std = @import("std");
const ascii = std.ascii;

pub const Method = enum(u4) {
    get,
    head,
    post,
    put,
    delete,
    connect,
    options,
    trace,
    patch,

    pub fn toString(self: Method) []const u8 {
        switch (self) {
            .get => return "GET",
            .head => return "HEAD",
            .post => return "POST",
            .put => return "PUT",
            .delete => return "DELETE",
            .connect => return "CONNECT",
            .options => return "OPTIONS",
            .trace => return "TRACE",
            .patch => return "PATCH",
        }
    }

    fn fromString(s: []const u8) !Method {
        if (ascii.eqlIgnoreCase(s, "GET")) {
            return .get;
        } else if (ascii.eqlIgnoreCase(s, "HEAD")) {
            return .head;
        } else if (ascii.eqlIgnoreCase(s, "POST")) {
            return .post;
        } else if (ascii.eqlIgnoreCase(s, "PUT")) {
            return .put;
        } else if (ascii.eqlIgnoreCase(s, "DELETE")) {
            return .delete;
        } else if (ascii.eqlIgnoreCase(s, "CONNECT")) {
            return .connect;
        } else if (ascii.eqlIgnoreCase(s, "OPTIONS")) {
            return .options;
        } else if (ascii.eqlIgnoreCase(s, "TRACE")) {
            return .trace;
        } else if (ascii.eqlIgnoreCase(s, "PATCH")) {
            return .patch;
        } else {
            return error.InvalidMethod;
        }
    }

    pub fn shouldHaveBody(self: Method) bool {
        switch (self) {
            .post, .put, .patch => return true,
            else => return false,
        }
    }
};