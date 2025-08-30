//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();
    defer _ = gpa.deinit();
    var random_raw = std.Random.DefaultPrng.init (@bitCast(std.time.milliTimestamp()));
    const random = random_raw.random();
    const row = 258;
    const col = 258;
    const ms = try lib.MatrixState.init (row, col, a);
    var machine = lib.Machine {
        .allocator = a,
        .random = random,
        .matrix_state = ms,
        .visitor = .{},
        .activated = .{},
        .todo_list = .{},
        .todo_offset = undefined,
        .p = undefined,
    };
    defer machine.deinit ();
    machine.visitor = try std.DynamicBitSetUnmanaged.initEmpty(a, row * col);
    try machine.init_p (2.0);
    try machine.init_values();
    try do_test (&machine);
}

pub fn do_test (m: *lib.Machine) !void {
    const STEP_CNT = 256 * 256 * 200;
    const start = std.time.milliTimestamp();
    for (0..STEP_CNT) |i| {
        _ = i; // autofix
        try m.step ();
    }
    const end = std.time.milliTimestamp();
    std.debug.print ("cost milli time: {d} ms.\n", .{ end - start });
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("automaton_0380_lib");
