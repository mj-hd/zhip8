const std = @import("std");

const sdl2_pkg = @import("sdl2.zig");

pub const Chip8 = struct {
    cycles: u16,
    status: Status,

    pc: u12,
    sp: u8,
    r: [16]u8,
    i: u16,

    mem: []u8,
    stack: [16]u12,
    pixels: []u8,

    vf: bool,

    key: [16]bool,
    delay_timer: u8,
    sound_timer: u8,

    pub fn new(alloc: *std.mem.Allocator) !Chip8 {
        return Chip8{
            .cycles = 0,
            .status = Status.running,
            .pc = 0x0200,
            .sp = 0,
            .r = [_]u8{0x00} ** 16,
            .i = 0x0000,
            .mem = try alloc.alloc(u8, 0x1000),
            .stack = [_]u12{0x00} ** 16,
            .pixels = try alloc.alloc(u8, 64 * 32 * 4),
            .vf = false,
            .key = [_]bool{false} ** 16,
            .delay_timer = 0,
            .sound_timer = 0,
        };
    }

    pub fn drop(self: *Chip8, alloc: *std.mem.Allocator) void {
        alloc.free(self.mem);
        alloc.free(self.pixels);
    }

    pub fn render(self: *Chip8, context: *sdl2_pkg.Context) !void {
        try context.update(self.pixels);
    }

    pub fn tick(self: *Chip8) !void {
        self.cycles += 1;

        switch (self.status) {
            Status.running => {},
            Status.key_waiting => return,
            Status.key_pressed => |val| {
                self.r[val.reg] = val.key;
            },
        }

        var data: u16 = (@intCast(u16, self.mem[self.pc]) << 8);
        data |= @intCast(u16, self.mem[self.pc + 1]);

        std.debug.print("PC: {x}, MNE: {x}\n", .{ self.pc, data });

        self.pc += 2;

        try self.decode_and_execute(data);
    }

    pub fn load(self: *Chip8, data: []u8) !void {
        std.mem.copy(u8, self.mem[0x0200..], data);
        std.mem.copy(u8, self.mem[0x0000..], fontset[0..]);
    }

    pub fn press(self: *Chip8, key: u4) !void {
        self.key[key] = true;

        switch (self.status) {
            Status.key_waiting => |s| {
                self.status = Status{
                    .key_pressed = .{
                        .reg = s.reg,
                        .key = key,
                    },
                };
            },
            else => {},
        }
    }

    pub fn release(self: *Chip8, key: u8) !void {
        self.key[key] = false;
    }

    fn decode_and_execute(self: *Chip8, data: u16) !void {
        const high = @intCast(u4, data >> 12);
        const nnn = @intCast(u12, data & 0x0FFF);
        const x = @intCast(u4, (data >> 8) & 0x000F);
        const y = @intCast(u4, (data >> 4) & 0x000F);
        const kk = @intCast(u8, data & 0x00FF);
        const nibble = @intCast(u4, data & 0x000F);

        try switch (high) {
            0x0 => {
                const low = data & 0x00FF;
                try switch (low) {
                    0xE0 => self.cls(),
                    0xEE => self.ret(),
                    else => self.sys(nnn),
                };
            },
            0x1 => self.jp(nnn),
            0x2 => self.call(nnn),
            0x3 => self.se_imm(x, kk),
            0x4 => self.sne_imm(x, kk),
            0x5 => self.se_reg(x, y),
            0x6 => self.ld_imm(x, kk),
            0x7 => self.add_imm(x, kk),
            0x8 => {
                const low = data & 0x000F;

                try switch (low) {
                    0x0 => self.ld_reg(x, y),
                    0x1 => self.or_reg(x, y),
                    0x2 => self.and_reg(x, y),
                    0x3 => self.xor_reg(x, y),
                    0x4 => self.add_reg(x, y),
                    0x5 => self.sub_reg(x, y),
                    0x6 => self.shr_reg(x),
                    0x7 => self.subn_reg(x, y),
                    0xE => self.shl_reg(x),
                    else => return error.unknown8Opecode,
                };
            },
            0x9 => self.sne_reg(x, y),
            0xA => self.ld_i_imm(nnn),
            0xB => self.jp_v0(nnn),
            0xC => self.rnd_imm(x, kk),
            0xD => self.drw_reg(x, y, nibble),
            0xE => {
                const low = data & 0x00FF;

                try switch (low) {
                    0x9E => self.skp(x),
                    0xA1 => self.sknp(x),
                    else => return error.unknownEOpecode,
                };
            },
            0xF => {
                const low = data & 0x00FF;

                try switch (low) {
                    0x07 => self.ld_reg_dt(x),
                    0x0A => self.ld_k(x),
                    0x15 => self.ld_dt_reg(x),
                    0x18 => self.ld_st_reg(x),
                    0x1E => self.add_i_reg(x),
                    0x29 => self.ld_f_x(x),
                    0x33 => self.ld_b_x(x),
                    0x55 => self.ld_block_write(x),
                    0x65 => self.ld_block_read(x),
                    else => return error.unknownFOpecode,
                };
            },
        };
    }

    fn sys(_: *Chip8, _: u12) !void {}

    pub fn cls(self: *Chip8) !void {
        var i: u16 = 0;
        // TODO
        while (i < 64 * 32 * 4) {
            self.pixels[i] = 0x00;
            i += 1;
        }
    }

    fn ret(self: *Chip8) !void {
        self.sp -%= 1;
        self.pc = self.stack[self.sp];
    }

    fn jp(self: *Chip8, addr: u12) !void {
        self.pc = addr;
    }

    fn call(self: *Chip8, addr: u12) !void {
        self.stack[self.sp] = self.pc;
        self.sp +%= 1;
        self.pc = addr;
    }

    fn se_imm(self: *Chip8, x: u4, imm: u8) !void {
        if (self.r[x] == imm) {
            self.pc +%= 2;
        }
    }

    fn sne_imm(self: *Chip8, x: u4, imm: u8) !void {
        if (self.r[x] != imm) {
            self.pc +%= 2;
        }
    }

    fn se_reg(self: *Chip8, x: u4, y: u4) !void {
        if (self.r[x] == self.r[y]) {
            self.pc +%= 2;
        }
    }

    fn ld_imm(self: *Chip8, x: u4, kk: u8) !void {
        self.r[x] = kk;
    }

    fn add_imm(self: *Chip8, x: u4, kk: u8) !void {
        self.r[x] +%= kk;
    }

    fn ld_reg(self: *Chip8, x: u4, y: u4) !void {
        self.r[x] = self.r[y];
    }

    fn or_reg(self: *Chip8, x: u4, y: u4) !void {
        self.r[x] |= self.r[y];
    }

    fn and_reg(self: *Chip8, x: u4, y: u4) !void {
        self.r[x] &= self.r[y];
    }

    fn xor_reg(self: *Chip8, x: u4, y: u4) !void {
        self.r[x] ^= self.r[y];
    }

    fn add_reg(self: *Chip8, x: u4, y: u4) !void {
        self.vf = @addWithOverflow(u8, self.r[x], self.r[y], &self.r[x]);
    }

    fn sub_reg(self: *Chip8, x: u4, y: u4) !void {
        self.vf = @subWithOverflow(u8, self.r[x], self.r[y], &self.r[x]);
    }

    fn shr_reg(self: *Chip8, x: u4) !void {
        self.vf = self.r[x] & 1 == 1;
        self.r[x] >>= 1;
    }

    fn subn_reg(self: *Chip8, x: u4, y: u4) !void {
        self.vf = @subWithOverflow(
            u8,
            self.r[y],
            @intCast(u3, self.r[x] & 0b111),
            &self.r[x],
        );
    }

    fn shl_reg(self: *Chip8, x: u4) !void {
        self.vf = @shlWithOverflow(
            u8,
            self.r[x],
            1,
            &self.r[x],
        );
    }

    fn sne_reg(self: *Chip8, x: u4, y: u4) !void {
        if (self.r[x] != self.r[y]) {
            self.pc += 2;
        }
    }

    fn ld_i_imm(self: *Chip8, addr: u12) !void {
        self.i = addr;
    }

    fn jp_v0(self: *Chip8, addr: u12) !void {
        self.pc = self.r[0] + addr;
    }

    fn rnd_imm(self: *Chip8, x: u4, imm: u8) !void {
        self.r[x] = imm; // TODO: rnd
    }

    fn drw_reg(self: *Chip8, x: u4, y: u4, nibble: u8) !void {
        var sx = @intCast(u16, self.r[x]);
        var sy = @intCast(u16, self.r[y]);

        self.vf = false;

        var addr = self.i;

        while (addr < self.i + nibble) {
            const row = self.mem[addr];

            var i: u16 = 0;

            while (i < 8) {
                const mask = @as(u8, 1) << @intCast(u3, 7 - i);
                const enable = (row & mask) != 0;
                const pos: u16 = (sy *% 64 +% sx +% i) *% 4;

                const prev_enable = self.pixels[pos] > 0x00;

                const color: u8 = if (enable != prev_enable) 0xFF else 0x00;

                self.pixels[pos] = color;
                self.pixels[pos + 1] = color;
                self.pixels[pos + 2] = color;
                self.pixels[pos + 3] = color;

                self.vf = self.vf or (prev_enable and enable);
                i += 1;
            }

            sy +%= 1;
            addr +%= 1;
        }
    }

    fn skp(self: *Chip8, x: u4) !void {
        if (self.key[self.r[x]]) {
            self.pc += 2;
        }
    }

    fn sknp(self: *Chip8, x: u4) !void {
        if (!self.key[self.r[x]]) {
            self.pc += 2;
        }
    }

    fn ld_reg_dt(self: *Chip8, x: u4) !void {
        self.r[x] = self.delay_timer;
    }

    fn ld_k(self: *Chip8, x: u4) !void {
        // 遅延してキーが押された次回以降のtickで設定される
        self.status = Status{
            .key_waiting = .{
                .reg = x,
            },
        };
    }

    fn ld_dt_reg(self: *Chip8, x: u4) !void {
        self.delay_timer = self.r[x];
    }

    fn ld_st_reg(self: *Chip8, x: u4) !void {
        self.sound_timer = self.r[x];
    }

    fn add_i_reg(self: *Chip8, x: u4) !void {
        self.i += self.r[x];
    }

    fn ld_f_x(self: *Chip8, x: u4) !void {
        self.i = 0x0000 + self.r[x] * 5;
    }

    fn ld_b_x(self: *Chip8, x: u4) !void {
        const val = self.r[x];
        self.mem[self.i + 2] = val % 10;
        self.mem[self.i + 1] = (val / 10) % 10;
        self.mem[self.i + 0] = (val / 100) % 10;
    }

    fn ld_block_write(self: *Chip8, x: u4) !void {
        var addr = self.i;
        var i: u4 = 0;
        while (addr < self.i + (x + 1)) {
            self.mem[addr] = self.r[i];
            addr += 1;
            i += 1;
        }
    }

    fn ld_block_read(self: *Chip8, x: u4) !void {
        var addr = self.i;
        var i: u4 = 0;
        while (addr < self.i + (x + 1)) {
            self.r[i] = self.mem[addr];
            addr += 1;
            i += 1;
        }
    }
};

const Status = union(enum) {
    running: void,
    key_waiting: struct { reg: u4 },
    key_pressed: struct { reg: u4, key: u4 },
};

const fontset = [80]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};
