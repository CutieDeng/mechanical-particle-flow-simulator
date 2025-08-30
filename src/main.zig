//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();
    defer _ = gpa.deinit();
    const data_file = try std.fs.cwd().createFileZ("output.data", .{});
    defer data_file.close();
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
        .writer = null,
    };
    defer machine.deinit ();
    machine.visitor = try std.DynamicBitSetUnmanaged.initEmpty(a, row * col);
    try machine.init_p (2.0);
    try machine.init_values();
    const writer_buffer = try a.alloc (u8, 0x1000000);
    defer a.free (writer_buffer);
    var w = data_file.writer(writer_buffer);
    machine.writer = &w.interface;

    const start = std.time.milliTimestamp();
    try do_test (&machine);
    try w.interface.flush();
    const end = std.time.milliTimestamp();
    std.debug.print ("cost milli time: {d} ms.\n", .{ end - start });
}

pub fn do_test (m: *lib.Machine) !void {
    const STEP_CNT = 256 * 256;
    const INNER_STEP_CNT = 200;
    for (0..STEP_CNT) |i| {
        for (0..INNER_STEP_CNT) |j| {
            try m.step ();
            _ = j;
        }
        try m.write();
        _ = i; // autofix
    }
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("automaton_0380_lib");
