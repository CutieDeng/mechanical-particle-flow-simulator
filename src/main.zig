pub fn main_machine() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();
    defer _ = gpa.deinit();
    const data_file = try std.fs.cwd().createFileZ("output.data", .{});
    defer data_file.close();
    var random_raw = std.Random.DefaultPrng.init (@bitCast(std.time.milliTimestamp()));
    // var random_raw = std.Random.Sfc64.init(@bitCast(std.time.milliTimestamp()));
    const random = random_raw.random();
    const row = 256;
    const col = 256;
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
        .init_val = undefined,
    };
    defer machine.deinit ();
    machine.visitor = try std.DynamicBitSetUnmanaged.initEmpty(a, row * col);

    const writer_buffer = try a.alloc (u8, 0x1000000);
    defer a.free (writer_buffer);
    var w = data_file.writer(writer_buffer);

    const ctx = Context {
        .write_buffer = writer_buffer,
        .data_file = &w.interface,
    };

    try simulator_exec2 (&machine, ctx, 0.2);
    try simulator_exec2 (&machine, ctx, 0.5);
    try simulator_exec2 (&machine, ctx, 5);
}

pub const Context = struct {
    write_buffer: []u8,
    data_file: *std.Io.Writer,
};

pub fn simulator_exec (m: *lib.Machine, ctx: Context, value: f32) !void {
    try m.init_p (value);
    try m.init_values();
    m.writer = ctx.data_file;

    const start = std.time.milliTimestamp();
    try do_test (m);
    if (m.writer) |w| {
        try w.flush();
    }
    const end = std.time.milliTimestamp();
    std.debug.print ("cost milli time: {d} ms.\n", .{ end - start });
    
    const std_buffer = try m.allocator.alloc (u8, 1024);
    defer m.allocator.free (std_buffer);
    const output = std.Progress.lockStderrWriter(std_buffer);
    defer std.Progress.unlockStderrWriter();

    try m.matrix_state.prettyPrint (output);
    try output.flush();
}

pub fn simulator_exec2(m: *lib.Machine, ctx: Context, value: f32) !void {
    try m.init_p (value);
    try m.init_values();
    m.writer = ctx.data_file;

    const sm = Simulator { .machine = m, };
    const start = std.time.milliTimestamp();
    const sm_val = try sm.run();
    const end = std.time.milliTimestamp();

    std.debug.print ("p: {d}\n", .{ value });
    std.debug.print ("cost milli time: {d} ms.\n", .{ end - start });
    std.debug.print ("val: {d}\n\n", .{ sm_val });
}

pub const Simulator = struct {
    const This = Simulator;
    machine: *lib.Machine,
    pub fn run(s: Simulator) !f64 {
        const PRE_SIMUALTE_COUNT = 10000;
        for (0..PRE_SIMUALTE_COUNT) |_| {
            try s.machine.step();
        }
        const BATCH_COUNT = 200;
        const ROUND = 10;
        var sum_var: i64 = 0;
        for (0..ROUND) |_| {
            for (0..BATCH_COUNT) |_| {
                try s.machine.step();
            }
            const s2 = @as(i64, @intCast(@abs (s.machine.matrix_state.sum())));
            sum_var += s2;
        }
        const sum_var_f64: f64 = @floatFromInt(sum_var);
        const element_sz = s.machine.matrix_state.data_col * s.machine.matrix_state.data_row * ROUND;
        const val = sum_var_f64 / @as(f64, @floatFromInt(element_sz));
        return val;
    }
};

pub fn do_test (m: *lib.Machine) !void {
    // const STEP_CNT = 256 * 256;
    const STEP_CNT = 1;
    // const INNER_STEP_CNT = 200;
    const INNER_STEP_CNT = 1;
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

pub const Simulator2 = struct {
    w: lib.World,
    pub fn exec(s: *Simulator2) !f64 {
        try s.w.post_init();
        const PRE_SIMUALTE_COUNT = 10000;
        for (0..PRE_SIMUALTE_COUNT) |_| {
            try s.w.wrap_step();
        }
        const BATCH_COUNT = 200;
        const ROUND = 10;
        var sum_var: i64 = 0;
        for (0..ROUND) |_| {
            for (0..BATCH_COUNT) |_| {
                try s.w.wrap_step();
            }
            const s2 = @as(i64, @intCast(s.w.abs()));
            std.debug.print ("abs: {d}\n", .{ s2 });
            sum_var += s2;
        }
        const sum_var_f64: f64 = @floatFromInt(sum_var);
        const element_sz = @as(usize, s.w.row) * @as(usize, s.w.col) * ROUND;
        const val = sum_var_f64 / @as(f64, @floatFromInt(element_sz));
        return val;
    }
};

pub fn main_world() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();
    defer _ = gpa.deinit();
    var random_raw = std.Random.DefaultPrng.init (@bitCast(std.time.milliTimestamp()));
    const random = random_raw.random();
    const row = 256;
    const col = 256;
    var w = try lib.World.init(row, col, a, random, 0);
    w.p = calc_p(2);
    std.debug.print ("p: {d}\n", .{ w.p });
    var s = Simulator2 { .w = w };
    defer s.w.deinit();
    const start_time = std.time.milliTimestamp();
    const e = try s.exec();
    const end_time = std.time.milliTimestamp();
    std.debug.print("val: {d}\n", .{ e });
    std.debug.print("time cost: {d} ms.\n", .{ end_time - start_time });
}

pub const main = main_world;

pub fn calc_p(t: f64) f64 {
    return 1 - std.math.exp (-2 * (1.0 / t));    
}