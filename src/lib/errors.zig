const std = @import("std");

pub const Errors = enum {
    InvalidStatusCode,
    InvalidMethod,
    InvalidUri,
    InvalidUriParts,
    InvalidHeaderName,
    InvalidHeaderValue,
};

pub const ParseError = error{
    StreamTooLong, // std.io.reader.readUntilDelimiterOrEof
    EndOfStream,
    InvalidStatusLine,
    UnsupportedVersion,
    InvalidHeader,
    InvalidEncodingHeader,
    InvalidChunkedPayload,
};
