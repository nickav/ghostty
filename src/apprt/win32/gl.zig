const win32 = @import("win32.zig");

pub const HDC = win32.HANDLE;
pub const HGLRC = win32.HANDLE;
pub const WORD = u16;
pub const BYTE = u8;

pub const CS_OWNDC: win32.UINT = 0x0020;

pub const PFD_DRAW_TO_WINDOW: win32.DWORD = 0x00000004;
pub const PFD_SUPPORT_OPENGL: win32.DWORD = 0x00000020;
pub const PFD_DOUBLEBUFFER: win32.DWORD = 0x00000001;
pub const PFD_TYPE_RGBA: BYTE = 0;
pub const PFD_MAIN_PLANE: BYTE = 0;

pub const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion: WORD = 1,
    dwFlags: win32.DWORD = 0,
    iPixelType: BYTE = 0,
    cColorBits: BYTE = 0,
    cRedBits: BYTE = 0,
    cRedShift: BYTE = 0,
    cGreenBits: BYTE = 0,
    cGreenShift: BYTE = 0,
    cBlueBits: BYTE = 0,
    cBlueShift: BYTE = 0,
    cAlphaBits: BYTE = 0,
    cAlphaShift: BYTE = 0,
    cAccumBits: BYTE = 0,
    cAccumRedBits: BYTE = 0,
    cAccumGreenBits: BYTE = 0,
    cAccumBlueBits: BYTE = 0,
    cAccumAlphaBits: BYTE = 0,
    cDepthBits: BYTE = 0,
    cStencilBits: BYTE = 0,
    cAuxBuffers: BYTE = 0,
    iLayerType: BYTE = 0,
    bReserved: BYTE = 0,
    dwLayerMask: win32.DWORD = 0,
    dwVisibleMask: win32.DWORD = 0,
    dwDamageMask: win32.DWORD = 0,
};

pub extern "user32" fn GetDC(hwnd: win32.HWND) callconv(.winapi) ?HDC;

pub extern "user32" fn ReleaseDC(hwnd: win32.HWND, hdc: HDC) callconv(.winapi) c_int;

pub extern "gdi32" fn ChoosePixelFormat(
    hdc: HDC,
    ppfd: *const PIXELFORMATDESCRIPTOR,
) callconv(.winapi) c_int;

pub extern "gdi32" fn SetPixelFormat(
    hdc: HDC,
    format: c_int,
    ppfd: *const PIXELFORMATDESCRIPTOR,
) callconv(.winapi) win32.BOOL;

pub extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.winapi) win32.BOOL;

pub extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.winapi) ?HGLRC;

pub extern "opengl32" fn wglMakeCurrent(hdc: ?HDC, hglrc: ?HGLRC) callconv(.winapi) win32.BOOL;

pub extern "opengl32" fn wglDeleteContext(hglrc: HGLRC) callconv(.winapi) win32.BOOL;

pub extern "opengl32" fn wglGetProcAddress(name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
