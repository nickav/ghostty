/// This is the main entrypoint to the apprt for Ghostty on windows.
/// Ghostty will initialize this in main to start the application..
const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");
const configpkg = @import("../../config.zig");
const Config = configpkg.Config;
const input = @import("../../input.zig");
const global = @import("../../global.zig");

const win32 = @import("./win32.zig");
const gl = @import("./gl.zig");
const Surface = @import("Surface.zig");

const log = std.log.scoped(.win32);

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindowClass");

// @Sync: must stay in sync with dist/windows/ghostty.rc's ID_ICON_GHOSTTY
const ID_ICON_GHOSTTY: usize = 1;

const WM_WAKEUP: win32.UINT = win32.WM_APP + 1;

pub const must_draw_from_app_thread = true;

core_app: *CoreApp,
hwnd: win32.HWND,
bg_brush: win32.HBRUSH,
use_light_theme: win32.DWORD = 0,
surface: ?*Surface,

gl_hdc: ?gl.HDC = null,
gl_hglrc: ?gl.HGLRC = null,

// @Incomplete: this is per-window state
g_placement: win32.WINDOWPLACEMENT = std.mem.zeroes(win32.WINDOWPLACEMENT),
// @Incomplete: this is per-window state
high_surrogate: win32.WCHAR,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    self.core_app = core_app;

    var config = Config.load(core_app.alloc) catch |err| err: {
        log.warn("error loading configuration, using defaults err={}", .{err});
        break :err try Config.default(core_app.alloc);
    };
    defer config.deinit();

    const use_pos = config.@"window-position-x" != null and config.@"window-position-y" != null;
    const initial_x: c_int = if (use_pos) config.@"window-position-x".? else win32.CW_USEDEFAULT;
    const initial_y: c_int = if (use_pos) config.@"window-position-y".? else win32.CW_USEDEFAULT;

    const title_w = try std.unicode.utf8ToUtf16LeAllocZ(
        core_app.alloc,
        config.title orelse "Ghostty",
    );
    defer core_app.alloc.free(title_w);

    // NOTE: we want to use a DPI-aware window
    if (false) {}
    else if (win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) |_| {}
    else if (win32.SetProcessDpiAwareness(win32.PROCESS_SYSTEM_DPI_AWARE)) |_| {}
    else {
        _ = win32.SetProcessDPIAware();
    }

    // NOTE: we want to tell windows to match the app to the user's preferred color scheme (light or dark)
    _ = win32.SetPreferredAppMode(1);

    const hinstance = win32.GetModuleHandleW(null) orelse {
        log.err("GetModuleHandleW failed", .{});
        return error.Win32GetModuleHandleFailed;
    };

    const icon = win32.LoadIconW(hinstance, win32.makeIntResource(ID_ICON_GHOSTTY));
    if (icon == null) {
        log.warn("LoadIconW failed err={}", .{win32.GetLastError()});
    }

    const wc: win32.WNDCLASSEXW = .{
        .style = gl.CS_OWNDC,
        .lpfnWndProc = &wndProc,
        .hInstance = hinstance,
        .hIcon = icon,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .lpszClassName = class_name,
        .hIconSm = icon,
    };
    if (win32.RegisterClassExW(&wc) == 0) {
        log.err("RegisterClassExW failed err={}", .{win32.GetLastError()});
        return error.Win32RegisterClassFailed;
    }

    self.bg_brush = @ptrCast(win32.GetStockObject(win32.BLACK_BRUSH));
    const hwnd = win32.CreateWindowExW(
        0,
        class_name,
        title_w,
        win32.WS_OVERLAPPEDWINDOW,
        initial_x,
        initial_y,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        null,
        null,
        hinstance,
        self,
    ) orelse {
        log.err("CreateWindowExW failed err={}", .{win32.GetLastError()});
        return error.Win32CreateWindowFailed;
    };

    //
    // NOTE(nick): this is a hack to get this working at all
    // In the future, surface should own it's own HWND (unless we only want one copy of the app per window, which would maybe work as well).
    // Either way, this needs to be thought through more!
    // :SurfaceShouldOwnTheHWND
    //
    self.hwnd = hwnd;

    const surface = try core_app.alloc.create(Surface);
    errdefer core_app.alloc.destroy(surface);
    try surface.init(self, &config);
    try core_app.addSurface(surface);
    self.surface = surface;
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    _ = self;
    _ = value;
    switch (action) {
        .render => switch (target) {
            .surface => |surface| surface.draw() catch |err| {
                log.warn("error drawing surface err={}", .{err});
            },
            .app => {},
        },

        .initial_size => {
            // @Robustness: this will be called before App.init() is called??
            
            // :SurfaceShouldOwnTheHWND
            // var rect: win32.RECT = .{ .left = 0, .top = 0, .right = @intCast(value.width), .bottom = @intCast(value.height) };
            // _ = win32.AdjustWindowRect(&rect, win32.WS_OVERLAPPEDWINDOW, 0);
            // _ = win32.SetWindowPos(self.hwnd, null, 0, 0, rect.right - rect.left, rect.bottom - rect.top, win32.SWP_NOMOVE | win32.SWP_NOZORDER);
        },

        // Acknowledged but not acted on yet.
        .quit_timer, .cell_size, .size_limit => {},

        else => return false,
    }

    return true;
}

pub fn run(self: *App) !void {
    _ = win32.ShowWindow(self.hwnd, win32.SW_SHOWDEFAULT);
    _ = win32.UpdateWindow(self.hwnd);

    // Without this, sleeping on windows is very inaccurate.
    _ = win32.timeBeginPeriod(1);

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
}

pub fn terminate(self: *App) void {
    _ = self;
}

pub fn wakeup(self: *App) void {
    _ = win32.PostMessageW(self.hwnd, WM_WAKEUP, 0, 0);
}

pub fn performIpc(
    _: Allocator,
    _: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    _: apprt.ipc.Action.Value(action),
) !bool {
    return false;
}

fn wndProc(
    hwnd: win32.HWND,
    msg: win32.UINT,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    switch (msg) {
        win32.WM_CLOSE => {
            _ = win32.DestroyWindow(hwnd);
            return 0;
        },
        win32.WM_CREATE => {
            const cs: *win32.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const self: *App = @ptrCast(@alignCast(cs.lpCreateParams));
            _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @bitCast(@intFromPtr(self)));
            self.hwnd = hwnd;
            self.updateTheme();
            return win32.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        WM_WAKEUP => {
            const self: *App = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));
            self.core_app.tick(self) catch |err| {
                log.warn("error ticking core app err={}", .{err});
            };
            return 0;
        },
        win32.WM_PAINT => {
            var ps: win32.PAINTSTRUCT = undefined;
            _ = win32.BeginPaint(hwnd, &ps);
            // win32_resize_callback(window_handle);
            _ = win32.EndPaint(hwnd, &ps);
            return win32.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win32.WM_SIZE => {
            const self: *App = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));
            
            if (self.surface) |surface| {
                var rect: win32.RECT = undefined;
                _ = win32.GetClientRect(hwnd, &rect);

                const width: u32 = @intCast(rect.right - rect.left);
                const height: u32 = @intCast(rect.bottom - rect.top);

                if (@hasDecl(@TypeOf(surface.core().renderer.api), "resizeViewport")) {
                    surface.core().renderer.api.resizeViewport(width, height);
                }

                surface.core().sizeCallback(.{ .width = width, .height = height }) catch |err| {
                    log.warn("error handling resize err={}", .{err});
                };

                surface.core().draw() catch |err| {
                    log.warn("error drawing surface err={}", .{err});
                };
            }

            return 0;
        },
        win32.WM_SYSCOMMAND => {
            switch (wparam) {
                // User trying to access application menu using ALT
                win32.SC_KEYMENU => {
                    // NOTE(nick): prevent beep sound when pressing alt key combo (e.g. alt + enter)
                    return 0;
                },
                else => {},
            }
        },
        win32.WM_KEYDOWN,
        win32.WM_KEYUP,
        win32.WM_SYSKEYDOWN,
        win32.WM_SYSKEYUP => {
            const self: *App = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));

            if (!win32.wasKeyDown(lparam) and win32.isKeyDown(lparam)) {
                if (wparam == win32.VK_F11) {
                    win32.toggleFullscreen(self.hwnd, &self.g_placement);
                }

                // @Incomplete: @Robustness: holding Enter down shouldn't continuously cycle the window...
                if (win32.GetKeyState(win32.VK_MENU) < 0 and wparam == win32.VK_RETURN) {
                    win32.toggleFullscreen(self.hwnd, &self.g_placement);
                }
            }

            var mods: input.Mods = .{};
            if (win32.GetKeyState(win32.VK_CONTROL) < 0) {
                mods.ctrl = true;
            }
            if (win32.GetKeyState(win32.VK_SHIFT) < 0) {
                mods.shift = true;
            }
            if (win32.GetKeyState(win32.VK_MENU) < 0) {
                mods.alt = true;
            }
            if (win32.GetKeyState(win32.VK_LWIN) < 0 or win32.GetKeyState(win32.VK_RWIN) < 0) {
                mods.super = true;
            }

            const action: input.Action = if (msg == win32.WM_KEYUP or msg == win32.WM_SYSKEYUP)
                .release
            else if (win32.wasKeyDown(lparam))
                .repeat
            else
                .press;

            const key = mapKey(lparam);

            const event: input.KeyEvent = .{
                .action = action,
                .key = key,
                .mods = mods,
                .unshifted_codepoint = blk: {
                    const result = win32.MapVirtualKeyW(@intCast(wparam), win32.MAPVK_VK_TO_CHAR);
                    // High bit set means it's a dead key; low 16 bits are the char.
                    const cp: u21 = @intCast(result & 0xFFFF);
                    break :blk if (cp > 0) cp else 0;
                },
                // .consumed_mods = ,
            };

            if (self.surface) |surface| {
                if (event.key != input.Key.unidentified) {
                    const effect = surface.core().keyCallback(event) catch |err| effect: {
                        std.log.err("keyCallback failed: {}", .{err});
                        break :effect .ignored;
                    };
                    _ = effect;
                }
            }

            return win32.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win32.WM_CHAR, win32.WM_SYSCHAR => {
            const self: *App = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));

            const character: u16 = @truncate(wparam);
            if (character >= 0xd800 and character <= 0xdbff) {
                self.high_surrogate = @intCast(wparam);
            } else {
                var codepoint: u32 = 0;
                if (character >= 0xdc00 and character <= 0xdfff) {
                    if (self.high_surrogate != 0) {
                        codepoint += (@as(u32, self.high_surrogate) - 0xd800) << 10;
                        codepoint += @as(u32, character) - 0xdc00;
                        codepoint += 0x10000;
                    }
                } else {
                    codepoint = character;
                }

                self.high_surrogate = 0;
                if (codepoint == '\r') codepoint = '\n';
                if ((codepoint >= 32 and codepoint != 127) or codepoint == '\t' or codepoint == '\n') {
                    if (self.surface) |surface| {

                        if (std.math.cast(u21, codepoint)) |cp| {
                            var buf: [4]u8 = undefined;
                            if (std.unicode.utf8Encode(cp, &buf)) |len| {
                                const utf8_text = buf[0..len];

                                const event: input.KeyEvent = .{
                                    .utf8 = utf8_text,
                                };
                                log.warn("[TIMING] WM_CHAR keyCallback cp={d} t={d}ms", .{ cp, @divTrunc(std.Io.Timestamp.now(global.io(), .awake).nanoseconds, std.time.ns_per_ms) });
                                const effect = surface.core().keyCallback(event) catch |err| effect: {
                                    std.log.err("keyCallback failed: {}", .{err});
                                    break :effect .ignored;
                                };
                                _ = effect;

                            } else |err| {
                                log.warn("failed to encode codepoint err={}", .{err});
                            }
                        }

                    }
                }
            }
        },
        // @Incomplete:
        // win32.WM_UNICHAR => {},
        // win32.WM_IME_REQUEST => {},
        win32.WM_DPICHANGED => {
            const suggested: *win32.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            _ = win32.SetWindowPos(
                hwnd,
                win32.HWND_TOP,
                suggested.left,
                suggested.top,
                suggested.right - suggested.left,
                suggested.bottom - suggested.top,
                win32.SWP_NOACTIVATE | win32.SWP_NOZORDER,
            );
        },
        win32.WM_GETMINMAXINFO => {
            // const info: *win32.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lparam)));
            // const style: win32.WINDOW_STYLE = win32.WS_OVERLAPPEDWINDOW;
            // var wr: win32.RECT = .{ .left = 0, .top = 0, .right = @intCast(min_width), .bottom = @intCast(min_height) };
            // _ = win32.AdjustWindowRect(&wr, style, win32.FALSE);
            // const width: i32 = wr.right - wr.left;
            // const height: i32 = wr.bottom - wr.top;
            // info.ptMinTrackSize.x = width;
            // info.ptMinTrackSize.y = height;
            // return 0;
        },
        win32.WM_SETTINGCHANGE => {
            if (lparam != 0) {
                const str: [*:0]const u16 = @ptrFromInt(@as(usize, @bitCast(lparam)));
                const slice = std.mem.span(str);
                if (std.mem.eql(u16, slice, std.unicode.utf8ToUtf16LeStringLiteral("ImmersiveColorSet"))) {
                    const self: *App = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));
                    self.updateTheme();
                    _ = win32.InvalidateRect(hwnd, null, 1);
                }
            }
        },
        win32.WM_DWMCOLORIZATIONCOLORCHANGED => {
            const self: *App = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));
            self.updateTheme();
            _ = win32.InvalidateRect(hwnd, null, 1);
        },
        else => {},
    }

    return win32.DefWindowProcW(hwnd, msg, wparam, lparam);
}

fn updateTheme(self: *App) void {
    self.use_light_theme = 0;
    var dataSize: win32.DWORD = @sizeOf(win32.DWORD);
    const status = win32.RegGetValueA(
        win32.HKEY_CURRENT_USER,
        "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        "AppsUseLightTheme",
        win32.RRF_RT_ANY,
        null,
        &self.use_light_theme,
        &dataSize,
    );

    if (status == win32.ERROR_SUCCESS) {
        var value: win32.BOOL = if (self.use_light_theme == 0) 1 else 0;
        _ = win32.DwmSetWindowAttribute(self.hwnd, win32.DWMWA_USE_IMMERSIVE_DARK_MODE, &value, @sizeOf(win32.BOOL));
    }

    self.bg_brush = @ptrCast(win32.GetStockObject(if (self.use_light_theme == 0) win32.BLACK_BRUSH else win32.WHITE_BRUSH));
}

fn mapKey(lparam: win32.LPARAM) input.Key {
    const scan_code: u32 = @intCast((lparam >> 16) & 0xff);
    const extended: bool = (lparam >> 24) & 1 != 0;
    const native: u32 = scan_code | (if (extended) @as(u32, 0xe000) else 0);

    for (input.keycodes.entries) |entry| {
        if (entry.native == native) return entry.key;
    }

    return .unidentified;
}