const std = @import("std");
const assert = std.debug.assert;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const chip8_pkg = @import("chip8.zig");
const sdl2_pkg = @import("sdl2.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var context = try sdl2_pkg.Context.new();
    defer context.drop();

    var chip8 = try chip8_pkg.Chip8.new(&alloc);
    defer chip8.drop(&alloc);

    var file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();

    var buffer = try alloc.alloc(u8, 0x1000 - 0x0200);
    defer alloc.free(buffer);

    _ = try file.read(buffer);

    try chip8.load(buffer);
    try chip8.cls();

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    try switch (event.key.keysym.sym) {
                        c.SDLK_0 => chip8.press(0x00),
                        c.SDLK_1 => chip8.press(0x01),
                        c.SDLK_2 => chip8.press(0x02),
                        c.SDLK_3 => chip8.press(0x03),
                        c.SDLK_4 => chip8.press(0x04),
                        c.SDLK_5 => chip8.press(0x05),
                        c.SDLK_6 => chip8.press(0x06),
                        c.SDLK_7 => chip8.press(0x07),
                        c.SDLK_8 => chip8.press(0x08),
                        c.SDLK_9 => chip8.press(0x09),
                        c.SDLK_a => chip8.press(0x0A),
                        c.SDLK_b => chip8.press(0x0B),
                        c.SDLK_c => chip8.press(0x0C),
                        c.SDLK_d => chip8.press(0x0D),
                        c.SDLK_e => chip8.press(0x0E),
                        c.SDLK_f => chip8.press(0x0F),
                        else => {},
                    };
                },
                c.SDL_KEYUP => {
                    try switch (event.key.keysym.sym) {
                        c.SDLK_0 => chip8.release(0x00),
                        c.SDLK_1 => chip8.release(0x01),
                        c.SDLK_2 => chip8.release(0x02),
                        c.SDLK_3 => chip8.release(0x03),
                        c.SDLK_4 => chip8.release(0x04),
                        c.SDLK_5 => chip8.release(0x05),
                        c.SDLK_6 => chip8.release(0x06),
                        c.SDLK_7 => chip8.release(0x07),
                        c.SDLK_8 => chip8.release(0x08),
                        c.SDLK_9 => chip8.release(0x09),
                        c.SDLK_a => chip8.release(0x0A),
                        c.SDLK_b => chip8.release(0x0B),
                        c.SDLK_c => chip8.release(0x0C),
                        c.SDLK_d => chip8.release(0x0D),
                        c.SDLK_e => chip8.release(0x0E),
                        c.SDLK_f => chip8.release(0x0F),
                        else => {},
                    };
                },
                else => {},
            }

            try chip8.tick();

            try context.clear();

            try chip8.render(&context);

            c.SDL_Delay(17);
        }
    }
}
