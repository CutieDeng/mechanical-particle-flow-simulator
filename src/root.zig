//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

pub const State = struct {
    @"0": i8,

    const This = State;

    pub inline fn val (s: This) i8 {
        return s.@"0";
    }

    pub fn random_init (r: std.Random) This {
        const raw_value = r.int(i8);
        const value = std.math.clamp(raw_value, -127, 127);
        return .{ value };
    }

    pub fn revert (s: *This) void {
        s.@"0" = - s.@"0";
    }
};

pub const MatrixState = struct {
    data: [*]State,
    row: usize,
    col: usize,
    data_row: usize,
    data_col: usize,
    const This = @This();
    const sub_row = 8;
    const sub_col = 16;
    const sub_size = sub_row * sub_col;
    pub fn unsafe_ref (m: This, r: usize, c: usize) *State {
        const r1 = std.math.divFloor (usize, r, sub_row) catch unreachable;
        const r2 = std.math.rem (usize, r, sub_row) catch unreachable;
        const c1 = std.math.divFloor (usize, c, sub_col) catch unreachable;
        const c2 = std.math.rem (usize, c, sub_col) catch unreachable;
        const sub_offest = r2 * sub_col + c2;
        const offset = r1 * m.col + c1;
        return &m.data [offset * sub_size + sub_offest];
    }
    pub fn ref (m: This, r: usize, c: usize) ?*State {
        if (r >= m.data_row or c >= m.data_col) {
            return null;
        }
        return unsafe_ref(m, r, c);
    }
    pub fn init (r: usize, c: usize, a: std.mem.Allocator) !MatrixState {
        const rtop = std.math.divCeil(usize, r, sub_row) catch unreachable;
        const ctop = std.math.divCeil (usize, c, sub_col) catch unreachable;
        const sz = rtop * ctop * sub_size;
        const d = try a.alloc (State, sz);
        return .{
            .data = d.ptr,
            .data_row = r,
            .data_col = c,
            .row = rtop,
            .col = ctop, 
        };
    }
    pub fn deinit (m: MatrixState, a: std.mem.Allocator) void {
        a.free(m.data[0..m.row * m.col * sub_size]);
    }
    pub fn prettyPrint (m: MatrixState, output: *std.Io.Writer) !void {
        try output.print("(matrix #:row {d} #:col {d}\n", .{ m.data_row, m.data_row });
        for (0..m.data_row) |i| {
            try output.print("\t", .{});
            for (0..m.data_col) |j| {
                if (j != 0) {
                    try output.print(" ", .{});
                }
                try output.print("{d:2}", .{ m.ref(i, j).?.val() });
            }
            if (i + 1 == m.data_row) {
                try output.print(")", .{});
            }
            try output.print("\n", .{});
        }
    }
    pub fn sum (m: MatrixState) i64 {
        var s: i64 = 0;
        for (0..m.data_row) |i| {
            for (0..m.data_col) |j| {
                const t = m.unsafe_ref(i, j).@"0";
                s += t;
            }
        }
        return s;
    }
};

const Index = struct {
    row: usize,
    col: usize,
};

pub const Machine = struct {
    allocator: std.mem.Allocator,
    random: std.Random,
    matrix_state: MatrixState,
    visitor: std.DynamicBitSetUnmanaged,
    activated: std.DynamicBitSetUnmanaged,
    todo_list: std.ArrayListUnmanaged(Index),
    todo_offset: usize,
    p: i8,
    writer: ?*std.Io.Writer,
    init_val: i8,
    pub fn init_p (m: *Machine, beta: f32) !void {
        const raw_v = 1 - std.math.exp (-2 * beta);
        const raw_v_2 = (raw_v - 0.5) * 255;
        const raw_v_3 = std.math.floor(raw_v_2);
        const raw_v_4 : i8 = @intFromFloat(raw_v_3);
        m.p = raw_v_4;
        std.debug.print ("actual p: {d}\n", .{ m.p });
    }
    pub fn init_values (m: *Machine) !void {
        for (0..m.matrix_state.data_row) |r| {
            for (0..m.matrix_state.data_col) |c| {
                m.matrix_state.ref (r, c).?.@"0" = 1;
            }
        }
    }
    pub fn step (m: *Machine) !void {
        const index_row_select = m.random.intRangeLessThan(usize, 0, m.matrix_state.data_row); 
        const index_col_select = m.random.intRangeLessThan(usize, 0, m.matrix_state.data_col);
        m.visitor.unsetAll();
        m.todo_offset = 0;
        m.todo_list.clearRetainingCapacity();
        m.visitor.set(index_row_select * m.matrix_state.data_col + index_col_select);
        m.init_val = m.matrix_state.ref (index_row_select, index_col_select).?.val();
        try m.todo_list.append(m.allocator, .{ .row = index_row_select, .col = index_col_select, });
        while (true) {
            const need_repeat = try step_inner(m);
            if (!need_repeat) {
                break;
            }
        }
    }
    fn step_inner (m: *Machine) !bool {
        if (m.todo_offset >= m.todo_list.items.len) {
            return false;
        }
        const todo = m.todo_list.items[m.todo_offset];
        m.todo_offset += 1;
        const col0, const row0 = .{ todo.col, todo.row };
        const row1 = if (todo.row == 0) m.matrix_state.data_row - 1 else todo.row - 1;
        const col1 = if (todo.col == 0) m.matrix_state.data_col - 1 else todo.col - 1;
        const row2 = if (todo.row == m.matrix_state.data_row - 1) 0 else todo.row + 1;
        const col2 = if (todo.col == m.matrix_state.data_col - 1) 0 else todo.col + 1;
        const nxts: [4] Index = .{ 
            .{ .col = col0, .row = row1, },
            .{ .col = col0, .row = row2, },
            .{ .col = col1, .row = row0, },
            .{ .col = col2, .row = row0, },
        };
        const st = m.matrix_state.ref(todo.row, todo.col).?;
        if (st.val() == m.init_val) {
            if (m.random.intRangeLessThan(i8, -127, 127) <= m.p) {
                st.revert();
            }
        } else {
            return true;
        }
        inline for (nxts) |n| {
            const idx = n.row * m.matrix_state.data_col + n.col;
            if (!m.visitor.isSet(idx)) {
                m.visitor.set(idx);
                try m.todo_list.append(m.allocator, n);
            }
        }
        return true;
    }
    pub fn deinit (m: *Machine) void {
        m.visitor.deinit (m.allocator);
        m.activated.deinit (m.allocator);
        m.todo_list.deinit (m.allocator);
        m.matrix_state.deinit (m.allocator);
    }
    pub fn write (m: *Machine) !void {
        for (0..m.matrix_state.data_row) |r| {
            for (0..m.matrix_state.data_col) |c| {
                const e = m.matrix_state.ref (r, c).?.val();
                if (m.writer) |output| {
                    try output.writeByte(@bitCast(e));
                }
            }
        }
    }
};
