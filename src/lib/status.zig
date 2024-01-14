const std = @import("std");

pub const Status = enum(u10) {
    // informational
    continue_ = 100,
    switching_protocols = 101,

    // success
    ok = 200,
    created = 201,
    accepted = 202,
    no_content = 204,
    partial_content = 206,

    // redirection
    moved_permanently = 301,
    found = 302,
    not_modified = 304,
    temporary_redirect = 307,
    permanent_redirect = 308,

    // client error
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    not_acceptable = 406,
    gone = 410,
    too_many_requests = 429,

    // server error
    internal_server_error = 500,
    bad_gateway = 502,
    service_unavailable = 503,
    gateway_timeout = 504,

    pub fn fromString(str: []const u8) !Status {
        if (std.ascii.eqlIgnoreCase(str, "200")) {
            return .ok;
        } else if (std.ascii.eqlIgnoreCase(str, "201")) {
            return .created;
        } else if (std.ascii.eqlIgnoreCase(str, "204")) {
            return .accepted;
        } else if (std.ascii.eqlIgnoreCase(str, "206")) {
            return .partial_content;
        } else if (std.ascii.eqlIgnoreCase(str, "301")) {
            return .moved_permanently;
        } else if (std.ascii.eqlIgnoreCase(str, "302")) {
            return .found;
        } else if (std.ascii.eqlIgnoreCase(str, "304")) {
            return .not_modified;
        } else if (std.ascii.eqlIgnoreCase(str, "307")) {
            return .temporary_redirect;
        } else if (std.ascii.eqlIgnoreCase(str, "308")) {
            return .permanent_redirect;
        } else if (std.ascii.eqlIgnoreCase(str, "400")) {
            return .bad_request;
        } else if (std.ascii.eqlIgnoreCase(str, "401")) {
            return .unauthorized;
        } else if (std.ascii.eqlIgnoreCase(str, "403")) {
            return .forbidden;
        } else if (std.ascii.eqlIgnoreCase(str, "404")) {
            return .not_found;
        } else if (std.ascii.eqlIgnoreCase(str, "405")) {
            return .method_not_allowed;
        } else if (std.ascii.eqlIgnoreCase(str, "406")) {
            return .not_acceptable;
        } else if (std.ascii.eqlIgnoreCase(str, "410")) {
            return .gone;
        } else if (std.ascii.eqlIgnoreCase(str, "429")) {
            return .too_many_requests;
        } else if (std.ascii.eqlIgnoreCase(str, "500")) {
            return .internal_server_error;
        } else if (std.ascii.eqlIgnoreCase(str, "502")) {
            return .bad_gateway;
        } else if (std.ascii.eqlIgnoreCase(str, "503")) {
            return .service_unavailable;
        } else if (std.ascii.eqlIgnoreCase(str, "504")) {
            return .gateway_timeout;
        }  else {
            return error.InvalidStatus;
        }
    }

    pub fn toString(self: Status) []const u8 {
        switch (self) {
            // informational
            .continue_ => return "Continue",
            .switching_protocols => return "Switching Protocols",

            .ok => return "OK",
            .created => return "Created",
            .accepted => return "Accepted",
            .no_content => return "No Content",
            .partial_content => return "Partial Content",

            // redirection
            .moved_permanently => return "Moved Permanently",
            .found => return "Found",
            .not_modified => return "Not Modified",
            .temporary_redirect => return "Temporary Redirected",
            .permanent_redirect => return "Permanent Redirect",

            // client error
            .bad_request => return "Bad Request",
            .unauthorized => return "Unauthorized",
            .forbidden => return "Forbidden",
            .not_found => return "Not Found",
            .method_not_allowed => return "Method Not Allowed",
            .not_acceptable => return "Not Acceptable",
            .gone => return "Gone",
            .too_many_requests => return "Too Many Requests",

            // server error
            .internal_server_error => return "Internal Server Error",
            .bad_gateway => return "Bad Gateway",
            .service_unavailable => return "Service Unavailable",
            .gateway_timeout => return "Gateway Timeout",
        }
    }
};
