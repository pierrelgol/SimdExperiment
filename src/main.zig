const std = @import("std");

fn firstIndexOfScalarSimd(arg: *const TestCase) ?usize {
    const haystack = arg.string;
    const needle = arg.needle;
    const chunck_length: usize = std.simd.suggestVectorLength(u8) orelse 4;
    const not_found = std.math.maxInt(u8);
    const needle_mask = @as(@Vector(chunck_length, u8), @splat(needle));
    const select_mask = @as(@Vector(chunck_length, u8), @splat(not_found));
    const chunck_iota = std.simd.iota(usize, chunck_length);

    var window = std.mem.window(u8, haystack, chunck_length, chunck_length);
    var i: usize = 0;
    while (i + chunck_length < haystack.len) : (i += chunck_length) {
        const haystack_chunck: @Vector(chunck_length, u8) = if (window.next()) |chunck| chunck[0..chunck_length].* else return null;
        const boolean_vec = haystack_chunck == needle_mask;
        const result = @reduce(.Min, @select(usize, boolean_vec, chunck_iota, select_mask));
        if (result != not_found) {
            return result + i;
        }
    }

    return result: while (i < haystack.len) : (i += 1) {
        if (haystack[i] == needle) {
            break :result i;
        }
    } else break :result null;
}

fn firstIndexOfScalar(arg: *const TestCase) ?usize {
    const haystack = arg.string;
    const needle = arg.needle;
    for (haystack, 0..) |char, i| {
        if (char == needle) {
            return i;
        }
    }
    return null;
}

const TestCase = struct {
    string: []const u8,
    needle: u8,

    pub fn create(allocator: std.mem.Allocator, random: std.Random, min: usize, max: usize) !TestCase {
        const length = random.uintLessThan(usize, max) + min;
        const buffer = try allocator.alloc(u8, length);
        random.bytes(buffer);
        return .{
            .string = buffer,
            .needle = buffer[random.uintLessThan(usize, length)],
        };
    }

    pub fn destroy(self: *TestCase, allocator: std.mem.Allocator) void {
        allocator.free(self.string);
    }
};

pub fn Benchmark(comptime FnSignature: type, comptime FnArg: type) type {
    return struct {
        const ArgType = FnArg;
        const Self = @This();
        allocator: std.mem.Allocator,
        test_cases: std.ArrayListUnmanaged(ArgType),
        function_1: *const FnSignature,
        function_2: *const FnSignature,
        timer: std.time.Timer,
        total_test: usize = 0,
        total_time_1: usize,
        total_time_2: usize,
        rand: std.Random.DefaultPrng,

        pub fn init(allocator: std.mem.Allocator, f1: *const FnSignature, f2: *const FnSignature) Self {
            return .{
                .allocator = allocator,
                .test_cases = std.ArrayListUnmanaged(ArgType).empty,
                .function_1 = f1,
                .function_2 = f2,
                .timer = std.time.Timer.start() catch unreachable,
                .total_test = 0,
                .total_time_1 = 0,
                .total_time_2 = 0,
                .rand = std.Random.DefaultPrng.init((@abs(std.time.timestamp()))),
            };
        }

        pub fn setup(self: *Self, total_test: usize, min: usize, max: usize) !void {
            for (0..total_test) |_| {
                const case = try ArgType.create(self.allocator, self.rand.random(), min, max);
                try self.test_cases.append(self.allocator, case);
            }
            self.total_test = total_test;
        }

        pub fn bench(self: *Self) !void {
            self.total_time_1 = 0;
            self.total_time_2 = 0;

            self.timer.reset();
            for (self.test_cases.items) |*case| {
                _ = self.function_1(case);
                self.total_time_1 += self.timer.lap();
            }
            const avg_time_1 = self.total_time_1 / self.total_test;

            self.timer.reset();
            for (self.test_cases.items) |*case| {
                _ = self.function_2(case);
                self.total_time_2 += self.timer.lap();
            }
            const avg_time_2 = self.total_time_2 / self.total_test;

            std.debug.print("simd block_length for u8 = {d}\n", .{std.simd.suggestVectorLength(u8) orelse 0});
            std.debug.print("Benchmark results:\n", .{});
            std.debug.print("Function 1: Total time = {d} ns, Average time = {d} ns per call\n", .{ self.total_time_1, avg_time_1 });
            std.debug.print("Function 2: Total time = {d} ns, Average time = {d} ns per call\n", .{ self.total_time_2, avg_time_2 });
        }

        pub fn teardown(self: *Self) void {
            for (self.test_cases.items) |*case| {
                case.destroy(self.allocator);
            }
            self.test_cases.deinit(self.allocator);
        }
    };
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var bench = Benchmark(@TypeOf(firstIndexOfScalar), TestCase).init(allocator, firstIndexOfScalar, firstIndexOfScalarSimd);
    defer bench.teardown();

    const min = bench.rand.random().uintAtMost(usize, std.math.maxInt(u10));
    const max = bench.rand.random().uintAtMost(usize, std.math.maxInt(u20));
    std.debug.print("min length : {d} : max length : {d}\n", .{ min, max });
    try bench.setup(1000, min, max);
    try bench.bench();
}
