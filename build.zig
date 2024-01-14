const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "http",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

     _ = b.addModule("http", .{
        .root_source_file = .{ .path = "src/main.zig" },
    });

    b.installArtifact(lib);
    
}
