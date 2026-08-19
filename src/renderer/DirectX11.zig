//! Graphics API wrapper for DirectX11 on Windows.
pub const DirectX11 = @This();

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const apprt = @import("../apprt.zig");
const font = @import("../font/main.zig");
const configpkg = @import("../config.zig");
const math = @import("../math.zig");
const rendererpkg = @import("../renderer.zig");
const shadertoy = @import("shadertoy.zig");
const Renderer = rendererpkg.GenericRenderer(DirectX11);
const dx11 = @import("./directx11/d3d11.zig");

pub const GraphicsAPI = DirectX11;

pub const custom_shader_target: shadertoy.Target = .glsl;
pub const custom_shader_y_is_down = true;

pub const swap_chain_count = 1;

const log = std.log.scoped(.directx11);

alloc: Allocator,

/// Alpha blending mode.
blending: configpkg.Config.AlphaBlending,

device: *dx11.ID3D11Device,
context: *dx11.ID3D11DeviceContext,
swap_chain: *dx11.IDXGISwapChain,
back_buffer_rtv: *dx11.ID3D11RenderTargetView,

/// Size of the swap chain's back buffer. TODO: update on resize.
width: u32,
height: u32,

pub fn init(alloc: Allocator, opts: rendererpkg.Options) !DirectX11 {
    const hwnd: *anyopaque = switch (apprt.runtime) {
        apprt.win32 => @ptrCast(opts.rt_surface.app.hwnd),
        else => @compileError("DirectX11 only supports the win32 apprt"),
    };

    const size = opts.rt_surface.getSize() catch apprt.SurfaceSize{
        .width = 800,
        .height = 600,
    };

    var device: ?*dx11.ID3D11Device = null;
    var context: ?*dx11.ID3D11DeviceContext = null;
    var swap_chain: ?*dx11.IDXGISwapChain = null;
    var feature_level: c_int = 0;
    const feature_levels = [_]c_int{dx11.D3D_FEATURE_LEVEL_11_0};

    const swap_chain_desc: dx11.DXGI_SWAP_CHAIN_DESC = .{
        .buffer_desc = .{
            .width = size.width,
            .height = size.height,
        },
        .output_window = hwnd,
    };

    const hr = dx11.D3D11CreateDeviceAndSwapChain(
        null,
        dx11.D3D_DRIVER_TYPE_HARDWARE,
        null,
        0,
        &feature_levels,
        feature_levels.len,
        dx11.D3D11_SDK_VERSION,
        &swap_chain_desc,
        &swap_chain,
        &device,
        &feature_level,
        &context,
    );
    if (hr < 0) {
        log.err("D3D11CreateDeviceAndSwapChain failed hr=0x{x}", .{@as(u32, @bitCast(hr))});
        return error.D3D11CreateDeviceFailed;
    }
    errdefer dx11.safeRelease(device);
    errdefer dx11.safeRelease(context);
    errdefer dx11.safeRelease(swap_chain);

    const back_buffer_rtv = try createBackBufferRtv(device.?, swap_chain.?);

    return .{
        .alloc = alloc,
        .blending = opts.config.blending,
        .device = device.?,
        .context = context.?,
        .swap_chain = swap_chain.?,
        .back_buffer_rtv = back_buffer_rtv,
        .width = size.width,
        .height = size.height,
    };
}

fn createBackBufferRtv(
    device: *dx11.ID3D11Device,
    swap_chain: *dx11.IDXGISwapChain,
) !*dx11.ID3D11RenderTargetView {
    var back_buffer: ?*anyopaque = null;
    const gb_hr = swap_chain.GetBuffer(0, &dx11.IID_ID3D11Texture2D, &back_buffer);
    if (gb_hr < 0 or back_buffer == null) {
        log.err("IDXGISwapChain::GetBuffer failed hr=0x{x}", .{@as(u32, @bitCast(gb_hr))});
        return error.D3D11GetBufferFailed;
    }
    defer dx11.safeRelease(@as(?*dx11.ID3D11Texture2D, @ptrCast(back_buffer)));

    var rtv: ?*anyopaque = null;
    const rtv_hr = device.CreateRenderTargetView(back_buffer.?, null, &rtv);
    if (rtv_hr < 0 or rtv == null) {
        log.err("ID3D11Device::CreateRenderTargetView failed hr=0x{x}", .{@as(u32, @bitCast(rtv_hr))});
        return error.D3D11CreateRenderTargetViewFailed;
    }

    return @ptrCast(rtv.?);
}

pub fn deinit(self: *DirectX11) void {
    dx11.safeRelease(@as(?*dx11.ID3D11RenderTargetView, self.back_buffer_rtv));
    dx11.safeRelease(@as(?*dx11.IDXGISwapChain, self.swap_chain));
    dx11.safeRelease(@as(?*dx11.ID3D11DeviceContext, self.context));
    dx11.safeRelease(@as(?*dx11.ID3D11Device, self.device));
    self.* = undefined;
}

pub fn drawFrameStart(self: *DirectX11) void {
    const rtvs = [_]?*anyopaque{self.back_buffer_rtv};
    self.context.OMSetRenderTargets(1, &rtvs, null);

    // Cornflower blue -- the classic D3D "hello, clear color" value.
    const clear_color = [4]f32{ 0.392, 0.584, 0.929, 1.0 };
    self.context.ClearRenderTargetView(self.back_buffer_rtv, &clear_color);
}

pub fn drawFrameEnd(self: *DirectX11) void {
    _ = self;
}

pub fn surfaceSize(self: *const DirectX11) !struct { width: u32, height: u32 } {
    return .{ .width = self.width, .height = self.height };
}

pub fn initShaders(
    self: *const DirectX11,
    alloc: Allocator,
    custom_shaders: []const [:0]const u8,
) !shaders.Shaders {
    _ = alloc;
    return try shaders.Shaders.init(self.alloc, custom_shaders);
}

/// Initialize a new render target which can be presented by this API.
pub fn initTarget(self: *const DirectX11, width: usize, height: usize) !Target {
    _ = self;
    return .{ .width = width, .height = height };
}

/// Present the provided target. TODO: present via the DXGI swap chain.
pub fn present(self: *DirectX11, target: Target) !void {
    _ = self;
    _ = target;
    return error.Unimplemented;
}

pub fn presentLastTarget(self: *DirectX11) !void {
    const hr = self.swap_chain.Present(1, 0);
    if (hr < 0) {
        log.err("IDXGISwapChain::Present failed hr=0x{x}", .{@as(u32, @bitCast(hr))});
        return error.D3D11PresentFailed;
    }
}

pub fn beginFrame(
    self: *const DirectX11,
    renderer: *Renderer,
    target: *Target,
) !Frame {
    return try Frame.begin(.{}, renderer, target, self.context, self.back_buffer_rtv);
}

pub inline fn bufferOptions(self: DirectX11) BufferOptions {
    _ = self;
    return .{};
}
pub const instanceBufferOptions = bufferOptions;
pub const uniformBufferOptions = bufferOptions;
pub const fgBufferOptions = bufferOptions;
pub const bgBufferOptions = bufferOptions;
pub const imageBufferOptions = bufferOptions;
pub const bgImageBufferOptions = bufferOptions;
const BufferOptions = struct {};

pub inline fn textureOptions(self: DirectX11) Texture.Options {
    _ = self;
    return .{};
}

pub inline fn samplerOptions(self: DirectX11) Sampler.Options {
    _ = self;
    return .{};
}

pub const ImageTextureFormat = enum { gray, rgba, bgra };

pub inline fn imageTextureOptions(
    self: DirectX11,
    format: ImageTextureFormat,
    srgb: bool,
) Texture.Options {
    _ = self;
    _ = format;
    _ = srgb;
    return .{};
}

pub fn initAtlasTexture(
    self: *const DirectX11,
    atlas: *const font.Atlas,
) Texture.Error!Texture {
    _ = self;
    return .{ .width = atlas.size, .height = atlas.size };
}

// --- Render target / frame / render pass ---

pub const Target = struct {
    width: usize,
    height: usize,

    pub fn deinit(self: *Target) void {
        _ = self;
    }
};

pub const Frame = struct {
    renderer: *Renderer,
    target: *Target,
    context: *dx11.ID3D11DeviceContext,
    target_rtv: *dx11.ID3D11RenderTargetView,

    pub const Options = struct {};

    pub fn begin(
        opts: Options,
        renderer: *Renderer,
        target: *Target,
        context: *dx11.ID3D11DeviceContext,
        target_rtv: *dx11.ID3D11RenderTargetView,
    ) !Frame {
        _ = opts;
        return .{ .renderer = renderer, .target = target, .context = context, .target_rtv = target_rtv };
    }

    pub inline fn renderPass(
        self: *const Frame,
        attachments: []const RenderPass.Options.Attachment,
    ) RenderPass {
        return RenderPass.begin(.{ .attachments = attachments }, self.context, self.target_rtv);
    }

    /// Complete this frame and present the target.
    pub fn complete(self: *const Frame, sync: bool) void {
        _ = sync;
        // TODO: no health/error tracking yet, assume healthy.
        self.renderer.api.presentLastTarget() catch |err| {
            log.err("failed to present render target: err={}", .{err});
        };
        self.renderer.frameCompleted(.healthy);
    }
};

pub const RenderPass = struct {
    attachments: []const Options.Attachment,
    step_number: usize = 0,
    context: *dx11.ID3D11DeviceContext,
    target_rtv: *dx11.ID3D11RenderTargetView,

    pub const Options = struct {
        attachments: []const Attachment,

        pub const Attachment = struct {
            target: union(enum) {
                texture: Texture,
                target: Target,
            },
            clear_color: ?[4]f32 = null,
        };
    };

    pub const Step = struct {
        pipeline: Pipeline,
        uniforms: ?RawBuffer = null,
        buffers: []const ?RawBuffer = &.{},
        textures: []const ?Texture = &.{},
        samplers: []const ?Sampler = &.{},
        draw: Draw,

        pub const Draw = struct {
            type: PrimitiveType,
            vertex_count: usize,
            instance_count: usize = 1,
        };
    };

    pub fn begin(
        opts: Options,
        context: *dx11.ID3D11DeviceContext,
        target_rtv: *dx11.ID3D11RenderTargetView,
    ) RenderPass {
        const rtvs = [_]?*anyopaque{target_rtv};
        context.OMSetRenderTargets(1, &rtvs, null);

        if (opts.attachments.len > 0) {
            if (opts.attachments[0].clear_color) |c| {
                context.ClearRenderTargetView(target_rtv, &c);
            }
        }

        return .{ .attachments = opts.attachments, .context = context, .target_rtv = target_rtv };
    }

    pub fn step(self: *RenderPass, s: Step) void {
        defer self.step_number += 1;
        if (s.pipeline.is_bg_color) {
            const raw = s.uniforms orelse return;
            if (raw.data.len < @sizeOf(shaders.Uniforms)) return;
            const uniforms: *const shaders.Uniforms = @ptrCast(@alignCast(raw.data.ptr));
            const c = uniforms.bg_color;
            const color = [4]f32{
                @as(f32, @floatFromInt(c[0])) / 255.0,
                @as(f32, @floatFromInt(c[1])) / 255.0,
                @as(f32, @floatFromInt(c[2])) / 255.0,
                @as(f32, @floatFromInt(c[3])) / 255.0,
            };

            self.context.ClearRenderTargetView(self.target_rtv, &color);
        }
    }

    pub fn complete(self: *const RenderPass) void {
        _ = self;
    }
};

pub const PrimitiveType = enum { triangle, triangle_strip };

pub const RawBuffer = struct {
    len: usize = 0,
    data: []const u8 = &.{},
};

pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: RawBuffer = .{},
        len: usize = 0,

        pub const Options = BufferOptions;

        pub fn init(opts: Options, len: usize) !Self {
            _ = opts;
            return .{ .len = len };
        }

        pub fn initFill(opts: Options, data: []const T) !Self {
            _ = opts;
            return .{ .len = data.len };
        }

        pub fn deinit(self: Self) void {
            _ = self;
        }

        pub fn sync(self: *Self, data: []const T) !void {
            self.len = data.len;
            self.buffer.data = std.mem.sliceAsBytes(data);
        }

        pub fn syncFromArrayLists(
            self: *Self,
            lists: []const std.ArrayListUnmanaged(T),
        ) !usize {
            _ = self;
            var n: usize = 0;
            for (lists) |l| n += l.items.len;
            return n;
        }
    };
}

pub const Sampler = struct {
    pub const Options = struct {
        min_filter: FilterMode = .linear,
        mag_filter: FilterMode = .linear,
        wrap_s: WrapMode = .clamp_to_edge,
        wrap_t: WrapMode = .clamp_to_edge,

        pub const FilterMode = enum { linear, nearest };
        pub const WrapMode = enum { clamp_to_edge, repeat };
    };
    pub const Error = error{};

    pub fn init(opts: Options) Error!Sampler {
        _ = opts;
        return .{};
    }

    pub fn deinit(self: Sampler) void {
        _ = self;
    }
};

pub const Texture = struct {
    width: usize = 0,
    height: usize = 0,

    pub const Options = struct {
        format: PixelFormat = .rgba,
        internal_format: PixelFormat = .rgba,
        target: TextureTarget = .@"2D",
        min_filter: Sampler.Options.FilterMode = .linear,
        mag_filter: Sampler.Options.FilterMode = .linear,
        wrap_s: Sampler.Options.WrapMode = .clamp_to_edge,
        wrap_t: Sampler.Options.WrapMode = .clamp_to_edge,

        pub const PixelFormat = enum { red, rgba, bgra, srgba };
        pub const TextureTarget = enum { @"2D", Rectangle };
    };
    pub const Error = error{};

    pub fn init(
        opts: Options,
        width: usize,
        height: usize,
        data: ?[]const u8,
    ) Error!Texture {
        _ = opts;
        _ = data;
        return .{ .width = width, .height = height };
    }

    pub fn deinit(self: Texture) void {
        _ = self;
    }

    pub fn replaceRegion(
        self: Texture,
        x: usize,
        y: usize,
        width: usize,
        height: usize,
        data: []const u8,
    ) !void {
        _ = self;
        _ = x;
        _ = y;
        _ = width;
        _ = height;
        _ = data;
    }
};

pub const Pipeline = struct {
    stride: usize = 0,
    blending_enabled: bool = false,
    is_bg_color: bool = false,

    pub const Options = struct {
        vertex_fn: [:0]const u8,
        fragment_fn: [:0]const u8,
        step_fn: StepFunction = .per_vertex,
        blending_enabled: bool = true,

        pub const StepFunction = enum { constant, per_vertex, per_instance };
    };

    pub fn init(comptime VertexAttributes: ?type, opts: Options) !Pipeline {
        return .{
            .stride = if (VertexAttributes) |VA| @sizeOf(VA) else 0,
            .blending_enabled = opts.blending_enabled,
        };
    }

    pub fn deinit(self: *const Pipeline) void {
        _ = self;
    }
};

pub const shaders = struct {
    const pipeline_descs: []const struct { [:0]const u8, PipelineDescription } = &.{
        .{ "bg_color", .{
            .vertex_fn = "// TODO: bg_color.vs.hlsl",
            .fragment_fn = "// TODO: bg_color.ps.hlsl",
            .blending_enabled = false,
        } },
        .{ "cell_bg", .{
            .vertex_fn = "// TODO: cell_bg.vs.hlsl",
            .fragment_fn = "// TODO: cell_bg.ps.hlsl",
            .blending_enabled = true,
        } },
        .{ "cell_text", .{
            .vertex_attributes = CellText,
            .vertex_fn = "// TODO: cell_text.vs.hlsl",
            .fragment_fn = "// TODO: cell_text.ps.hlsl",
            .step_fn = .per_instance,
            .blending_enabled = true,
        } },
        .{ "image", .{
            .vertex_attributes = Image,
            .vertex_fn = "// TODO: image.vs.hlsl",
            .fragment_fn = "// TODO: image.ps.hlsl",
            .step_fn = .per_instance,
            .blending_enabled = true,
        } },
        .{ "bg_image", .{
            .vertex_attributes = BgImage,
            .vertex_fn = "// TODO: bg_image.vs.hlsl",
            .fragment_fn = "// TODO: bg_image.ps.hlsl",
            .step_fn = .per_instance,
            .blending_enabled = true,
        } },
    };

    const PipelineDescription = struct {
        vertex_attributes: ?type = null,
        vertex_fn: [:0]const u8,
        fragment_fn: [:0]const u8,
        step_fn: Pipeline.Options.StepFunction = .per_vertex,
        blending_enabled: bool = true,

        fn initPipeline(self: PipelineDescription) !Pipeline {
            return try .init(self.vertex_attributes, .{
                .vertex_fn = self.vertex_fn,
                .fragment_fn = self.fragment_fn,
                .step_fn = self.step_fn,
                .blending_enabled = self.blending_enabled,
            });
        }
    };

    const PipelineCollection = t: {
        const StructField = std.builtin.Type.StructField;

        var names: [pipeline_descs.len][]const u8 = undefined;
        var types = [_]type{Pipeline} ** pipeline_descs.len;
        var attrs = [_]StructField.Attributes{.{ .@"align" = @alignOf(Pipeline) }} ** pipeline_descs.len;

        for (pipeline_descs, &names) |pipeline, *name| {
            name.* = pipeline[0];
        }
        break :t @Struct(.auto, null, &names, &types, &attrs);
    };

    pub const Shaders = struct {
        pipelines: PipelineCollection,
        post_pipelines: []const Pipeline,
        defunct: bool = false,

        pub fn init(
            alloc: Allocator,
            post_shaders: []const [:0]const u8,
        ) !Shaders {
            _ = post_shaders;

            var pipelines: PipelineCollection = undefined;
            var initialized_pipelines: usize = 0;

            errdefer inline for (pipeline_descs, 0..) |pipeline, i| {
                if (i < initialized_pipelines) {
                    @field(pipelines, pipeline[0]).deinit();
                }
            };

            inline for (pipeline_descs) |pipeline| {
                var p = try pipeline[1].initPipeline();
                p.is_bg_color = comptime std.mem.eql(u8, pipeline[0], "bg_color");
                @field(pipelines, pipeline[0]) = p;
                initialized_pipelines += 1;
            }

            _ = alloc;
            return .{
                .pipelines = pipelines,
                .post_pipelines = &.{},
            };
        }

        pub fn deinit(self: *Shaders, alloc: Allocator) void {
            _ = alloc;
            if (self.defunct) return;
            self.defunct = true;

            inline for (pipeline_descs) |pipeline| {
                @field(self.pipelines, pipeline[0]).deinit();
            }
        }
    };

    // @Robustness: need to verify the alignment is correct here for DX11
    pub const Uniforms = extern struct {
        projection_matrix: math.Mat align(16),
        screen_size: [2]f32 align(8),
        cell_size: [2]f32 align(8),
        grid_size: [2]u16 align(4),
        grid_padding: [4]f32 align(16),
        padding_extend: PaddingExtend align(4),
        min_contrast: f32 align(4),
        cursor_pos: [2]u16 align(4),
        cursor_color: [4]u8 align(4),
        bg_color: [4]u8 align(4),
        bools: Bools align(4),

        const Bools = packed struct(u32) {
            cursor_wide: bool,
            use_display_p3: bool,
            use_linear_blending: bool,
            use_linear_correction: bool = false,
            _padding: u28 = 0,
        };

        const PaddingExtend = packed struct(u32) {
            left: bool = false,
            right: bool = false,
            up: bool = false,
            down: bool = false,
            _padding: u28 = 0,
        };
    };

    pub const CellText = extern struct {
        glyph_pos: [2]u32 align(8) = .{ 0, 0 },
        glyph_size: [2]u32 align(8) = .{ 0, 0 },
        bearings: [2]i16 align(4) = .{ 0, 0 },
        grid_pos: [2]u16 align(4),
        color: [4]u8 align(4),
        atlas: Atlas align(1),
        bools: packed struct(u8) {
            no_min_contrast: bool = false,
            is_cursor_glyph: bool = false,
            _padding: u6 = 0,
        } align(1) = .{},

        pub const Atlas = enum(u8) { grayscale = 0, color = 1 };
    };

    pub const CellBg = [4]u8;

    pub const Image = extern struct {
        grid_pos: [2]f32 align(8),
        cell_offset: [2]f32 align(8),
        source_rect: [4]f32 align(16),
        dest_size: [2]f32 align(8),
    };

    pub const BgImage = extern struct {
        opacity: f32 align(4),
        info: Info align(1),

        pub const Info = packed struct(u8) {
            position: Position,
            fit: Fit,
            repeat: bool,
            _padding: u1 = 0,

            pub const Position = enum(u4) { tl = 0, tc = 1, tr = 2, ml = 3, mc = 4, mr = 5, bl = 6, bc = 7, br = 8 };
            pub const Fit = enum(u2) { contain = 0, cover = 1, stretch = 2, none = 3 };
        };
    };
};