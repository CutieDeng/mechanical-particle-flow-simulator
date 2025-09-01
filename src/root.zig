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
    p: f64,
    writer: ?*std.Io.Writer,
    init_val: i8,
    pub fn init_p (m: *Machine, beta: f64) !void {
        const raw_v = 1 - std.math.exp (-2 * beta);
        m.p = raw_v;
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
        // if (!m.random_judge()) {
        //     return ;
        // }
        const index_row_select = m.random.intRangeLessThan(usize, 0, m.matrix_state.data_row); 
        const index_col_select = m.random.intRangeLessThan(usize, 0, m.matrix_state.data_col);
        m.visitor.unsetAll();
        m.todo_offset = 0;
        m.todo_list.clearRetainingCapacity();
        m.visitor.set(index_row_select * m.matrix_state.data_col + index_col_select);
        const st = m.matrix_state.ref (index_row_select, index_col_select).?;
        m.init_val = st.val();
        st.revert();
        try m.todo_list.append(m.allocator, .{ .row = index_row_select, .col = index_col_select, });
        while (true) {
            const need_repeat = try step_inner(m);
            if (!need_repeat) {
                break;
            }
        }
    }
    fn random_judge (m: Machine) bool {
        return m.random.float(f64) <= m.p;
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
        inline for (nxts) |n| {
            const idx = n.row * m.matrix_state.data_col + n.col;
            if (!m.visitor.isSet(idx)) {
                if (m.random_judge()) {
                    m.visitor.set(idx);
                    const st2 = m.matrix_state.ref(n.row, n.col).?;
                    if (st2.val() == m.init_val) {
                        st2.revert();
                        try m.todo_list.append(m.allocator, n);
                    }
                }
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

pub const World = struct {
    matrix: std.DynamicBitSetUnmanaged,
    row: u16,
    col: u16,
    a: std.mem.Allocator,
    r: std.Random,
    p_l: std.DynamicBitSetUnmanaged,
    p_r: std.DynamicBitSetUnmanaged,
    p_u: std.DynamicBitSetUnmanaged,
    p_d: std.DynamicBitSetUnmanaged,
    a_l: std.DynamicBitSetUnmanaged,
    a_r: std.DynamicBitSetUnmanaged,
    a_u: std.DynamicBitSetUnmanaged,
    a_d: std.DynamicBitSetUnmanaged,
    tmp: std.DynamicBitSetUnmanaged,
    v: std.DynamicBitSetUnmanaged,
    p: f64,
    pub fn select(w: *World, pb: *std.DynamicBitSetUnmanaged, a: *std.DynamicBitSetUnmanaged, offset: usize, row: ?usize) !void {
        a.setIntersection(pb.*);
        var it = a.iterator(.{});
        const sz = @as(usize, w.row) * @as(usize, w.col);
        while (it.next()) |i| {
            var i_2 = i + offset;
            if (row) |r| {
                const ic = i % r;
                if (ic + offset >= r) {
                    i_2 -= r;
                }
            } else if (i_2 >= sz) {
                i_2 -= sz;
            }
            if (w.matrix.isSet(i_2)) {
                w.a_l.set(i_2);
                w.a_r.set(i_2);
                w.a_u.set(i_2);
                w.a_d.set(i_2);
            }
        }
        w.v.setUnion(a.*);
        pb.toggleSet(a.*);
    }
    pub fn prepare_step(w: *World) !void {
        const sz = @as(usize, w.row) * @as(usize, w.col);
        for (0..sz) |i| {
            w.p_l.setValue(i, w.r.float(f64) < w.p);
        }
        for (0..sz) |i| {
            w.p_r.setValue(i, w.r.float(f64) < w.p);
        }
        for (0..sz) |i| {
            w.p_d.setValue(i, w.r.float(f64) < w.p);
        }
        for (0..sz) |i| {
            w.p_u.setValue(i, w.r.float(f64) < w.p);
        }
    }
    pub fn step(w: *World) !void {
        w.tmp.unsetAll();
        w.tmp.setUnion(w.a_l);
        w.a_l.unsetAll();
        try w.select(&w.p_l, &w.tmp, w.col - 1, w.col);
        w.tmp.unsetAll();
        w.tmp.setUnion(w.a_r);
        w.a_r.unsetAll();
        try w.select(&w.p_r, &w.tmp, 1, w.col);
        w.tmp.unsetAll();
        w.tmp.setUnion(w.a_d);
        w.a_d.unsetAll();
        try w.select(&w.p_d, &w.tmp, w.col, null);
        w.tmp.unsetAll();
        w.tmp.setUnion(w.a_u);
        w.a_u.unsetAll();
        try w.select(&w.p_u, &w.tmp, w.col * (w.row - 1), null);
    }
    pub fn wrap_step(w: *World) !void {
        try w.pre_step_1();
        try w.prepare_step(); 
        while (true) {
            try w.step();
            if (w.is_end()) {
                break;
            }
        }
        w.matrix.toggleSet(w.v);
    }
    pub fn pre_step_1(w: *World) !void {
        const idx = w.r.intRangeLessThan(usize, 0, @as(usize, w.row) * @as(usize, w.col));
        w.a_l.unsetAll();
        w.a_r.unsetAll();
        w.a_d.unsetAll();
        w.a_u.unsetAll();
        w.a_l.set(idx);
        w.a_r.set(idx);
        w.a_d.set(idx);
        w.a_u.set(idx);
        if (!w.matrix.isSet(idx)) {
            w.matrix.toggleAll();
        }
        w.v.unsetAll();
    }
    pub fn is_end(w: World) bool {
        return w.a_l.findFirstSet() == null;
    }
    pub fn count(w: World) usize {
        return w.matrix.count();
    }
    pub fn abs(w: World) usize {
        const c = w.count();
        const sz = @as(usize, w.row) * @as(usize, w.col);
        const c2 = c * 2;
        if (c2 >= sz) {
            return c2 - sz;
        } else {
            return sz - c2;
        }
    }
    pub fn init(row: u16, col: u16, a: std.mem.Allocator, r: std.Random, p: f64) !World {
        const sz = @as(usize, row) * @as(usize, col);
        var d0 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d0.deinit(a);
        var d1 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d1.deinit(a);
        var d2 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d2.deinit(a);
        var d3 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d3.deinit(a);
        var d4 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d4.deinit(a);
        var d5 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d5.deinit(a);
        var d6 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d6.deinit(a);
        var d7 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d7.deinit(a);
        var d8 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d8.deinit(a);
        var d9 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d9.deinit(a);
        var d10 = try std.DynamicBitSetUnmanaged.initEmpty(a, sz);
        errdefer d10.deinit(a);
        const w = World {
            .matrix = d0,
            .row = row,
            .col = col,
            .a = a,
            .r = r,
            .p_l = d1,
            .p_r = d2,
            .p_u = d3,
            .p_d = d4,
            .a_l = d5,
            .a_r = d6,
            .a_u = d7,
            .a_d = d8,
            .tmp = d9,
            .v = d10,
            .p = p,
        };
        return w;
    }
    pub fn post_init (w: *World) !void {
        w.matrix.setAll();
    }
    pub fn deinit (w: *World) void {
        w.matrix.deinit(w.a);
        w.p_l.deinit(w.a);
        w.p_r.deinit(w.a);
        w.p_u.deinit(w.a);
        w.p_d.deinit(w.a);
        w.a_l.deinit(w.a);
        w.a_r.deinit(w.a);
        w.a_u.deinit(w.a);
        w.a_d.deinit(w.a);
        w.tmp.deinit(w.a);
        w.v.deinit(w.a);
    }
};
