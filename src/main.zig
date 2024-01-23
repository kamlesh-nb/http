const std = @import("std");

const Request = @import("lib/request.zig");
const Response = @import("lib/response.zig");

const Person = struct {
        name: []const u8,
        age: i32,
    };

pub fn main() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }
    const allocator = gpa.allocator();

    const uri = try std.Uri.parse("https:://www.google.com");
    var request = try Request.new(allocator, uri, .get, .Http11);
    defer request.deinit();
    _ = try request.body.set(Person{ .name = "John Doe", .age = 20 });
    request.parts.headers.add("name", "oooop");

    const person = try request.body.get(allocator, Person);
    std.debug.print("\nname: {s} & age: {d}\n", .{ person.name, person.age });
    std.debug.print("\nuri: {s}, method: {s}, version: {s}\n", .{ request.parts.uri.scheme, request.parts.method.toString(), request.parts.version.toString() });
    std.debug.print("\nname: {s} \n", .{request.parts.headers.get("name").?});


    var response = try Response.new(allocator, .ok, .Http11);
    defer response.deinit();
    try response.body.set(Person{ .name = "Jane Doe", .age = 17 });
    response.parts.headers.add("name", "oooop");

    const pe = try response.body.get(allocator, Person);
    std.debug.print("\nname: {s} & age: {d}\n", .{ pe.name, pe.age });
    std.debug.print("\n status: {s} \n", .{response.parts.status.toString()});
    std.debug.print("\n version: {s} \n", .{response.parts.version.toString()});
    std.debug.print("\n name: {s} \n", .{response.parts.headers.get("name").?});

}