const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const Context = struct {
    renderer: *c.SDL_Renderer,
    window: *c.SDL_Window,
    texture: *c.SDL_Texture,

    pub fn new() !Context {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            return error.SDLInitializationFailure;
        }
        errdefer c.SDL_Quit();

        const window = c.SDL_CreateWindow("ZHIP-8", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 512, 256, c.SDL_WINDOW_OPENGL) orelse {
            return error.SDLInitializationFailure;
        };
        errdefer c.SDL_DestroyWindow(window);

        const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse {
            return error.SDLInitializationFailure;
        };
        errdefer c.SDL_DestroyRenderer(renderer);

        return Context{
            .renderer = renderer,
            .window = window,
            .texture = c.SDL_CreateTexture(
                renderer,
                c.SDL_PIXELFORMAT_ARGB8888,
                c.SDL_TEXTUREACCESS_STATIC,
                64,
                32,
            ).?,
        };
    }

    pub fn drop(self: *Context) void {
        c.SDL_Quit();

        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
    }

    pub fn clear(self: *Context) !void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, 0xFF, 0xFF, 0xFF, c.SDL_ALPHA_OPAQUE);
        _ = c.SDL_RenderClear(self.renderer);
    }

    pub fn update(self: *Context, pixels: []u8) !void {
        _ = c.SDL_UpdateTexture(self.texture, null, @ptrCast([*c]u8, pixels), 64 * 4);
        _ = c.SDL_RenderCopy(self.renderer, self.texture, null, null);
        _ = c.SDL_RenderPresent(self.renderer);
    }
};
