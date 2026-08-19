const HRESULT = i32;
const HMODULE = ?*anyopaque;
const UINT = u32;
const BOOL = c_int;

pub const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

pub const IID_ID3D11Texture2D: GUID = .{
    .data1 = 0x6f15aaf2,
    .data2 = 0xd208,
    .data3 = 0x4e89,
    .data4 = .{ 0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c },
};

pub const GenericMethod = *const anyopaque;

pub fn vtableOf(comptime VTable: type, self: anytype) *const VTable {
    return @as(*const *const VTable, @ptrCast(@alignCast(self))).*;
}

pub fn safeRelease(obj: anytype) void {
    const o = obj orelse return;
    _ = o.Release();
}

pub const IUnknownVTable = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
    Release: *const fn (*anyopaque) callconv(.winapi) u32,
};

pub const IDXGISwapChain = opaque {
    pub const VTable = extern struct {
        unknown: IUnknownVTable,
        // IDXGIObject: SetPrivateData, SetPrivateDataInterface, GetPrivateData, GetParent
        // IDXGIDeviceSubObject: GetDevice
        _pad0: [5]GenericMethod,
        Present: *const fn (*anyopaque, UINT, UINT) callconv(.winapi) HRESULT,
        GetBuffer: *const fn (*anyopaque, UINT, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    };

    pub fn AddRef(self: *IDXGISwapChain) u32 {
        return vtableOf(VTable, self).unknown.AddRef(self);
    }

    pub fn Release(self: *IDXGISwapChain) u32 {
        return vtableOf(VTable, self).unknown.Release(self);
    }

    pub fn Present(self: *IDXGISwapChain, sync_interval: UINT, flags: UINT) HRESULT {
        return vtableOf(VTable, self).Present(self, sync_interval, flags);
    }

    pub fn GetBuffer(self: *IDXGISwapChain, index: UINT, iid: *const GUID, out: *?*anyopaque) HRESULT {
        return vtableOf(VTable, self).GetBuffer(self, index, iid, out);
    }
};

// Up through ID3D11Device::CreateRenderTargetView (index 9).
pub const ID3D11Device = opaque {
    pub const VTable = extern struct {
        unknown: IUnknownVTable,
        // CreateBuffer, CreateTexture1D, CreateTexture2D, CreateTexture3D,
        // CreateShaderResourceView, CreateUnorderedAccessView
        _pad0: [6]GenericMethod,
        CreateRenderTargetView: *const fn (
            *anyopaque,
            *anyopaque,
            ?*const anyopaque,
            *?*anyopaque,
        ) callconv(.winapi) HRESULT,
    };

    pub fn AddRef(self: *ID3D11Device) u32 {
        return vtableOf(VTable, self).unknown.AddRef(self);
    }

    pub fn Release(self: *ID3D11Device) u32 {
        return vtableOf(VTable, self).unknown.Release(self);
    }

    pub fn CreateRenderTargetView(
        self: *ID3D11Device,
        resource: *anyopaque,
        desc: ?*const anyopaque,
        out: *?*anyopaque,
    ) HRESULT {
        return vtableOf(VTable, self).CreateRenderTargetView(self, resource, desc, out);
    }
};

// Up through ID3D11DeviceContext::ClearRenderTargetView (index 50).
pub const ID3D11DeviceContext = opaque {
    pub const VTable = extern struct {
        unknown: IUnknownVTable,
        // ID3D11DeviceChild: GetDevice, GetPrivateData, SetPrivateData, SetPrivateDataInterface
        _pad0: [4]GenericMethod,
        // VSSetConstantBuffers .. GSSetSamplers (indices 7-32)
        _pad1: [26]GenericMethod,
        OMSetRenderTargets: *const fn (
            *anyopaque,
            UINT,
            ?[*]const ?*anyopaque,
            ?*anyopaque,
        ) callconv(.winapi) void,
        // OMSetRenderTargetsAndUnorderedAccessViews .. CopyStructureCount (indices 34-49)
        _pad2: [16]GenericMethod,
        ClearRenderTargetView: *const fn (
            *anyopaque,
            *anyopaque,
            *const [4]f32,
        ) callconv(.winapi) void,
    };

    pub fn AddRef(self: *ID3D11DeviceContext) u32 {
        return vtableOf(VTable, self).unknown.AddRef(self);
    }

    pub fn Release(self: *ID3D11DeviceContext) u32 {
        return vtableOf(VTable, self).unknown.Release(self);
    }

    pub fn OMSetRenderTargets(
        self: *ID3D11DeviceContext,
        num_views: UINT,
        rtvs: ?[*]const ?*anyopaque,
        dsv: ?*anyopaque,
    ) void {
        vtableOf(VTable, self).OMSetRenderTargets(self, num_views, rtvs, dsv);
    }

    pub fn ClearRenderTargetView(
        self: *ID3D11DeviceContext,
        rtv: *anyopaque,
        color: *const [4]f32,
    ) void {
        vtableOf(VTable, self).ClearRenderTargetView(self, rtv, color);
    }
};

pub const ID3D11RenderTargetView = opaque {
    pub const VTable = IUnknownVTable;

    pub fn AddRef(self: *ID3D11RenderTargetView) u32 {
        return vtableOf(VTable, self).AddRef(self);
    }

    pub fn Release(self: *ID3D11RenderTargetView) u32 {
        return vtableOf(VTable, self).Release(self);
    }
};

pub const ID3D11Texture2D = opaque {
    pub const VTable = IUnknownVTable;

    pub fn AddRef(self: *ID3D11Texture2D) u32 {
        return vtableOf(VTable, self).AddRef(self);
    }

    pub fn Release(self: *ID3D11Texture2D) u32 {
        return vtableOf(VTable, self).Release(self);
    }
};

pub const DXGI_RATIONAL = extern struct {
    numerator: UINT = 0,
    denominator: UINT = 1,
};

pub const DXGI_SAMPLE_DESC = extern struct {
    count: UINT = 1,
    quality: UINT = 0,
};

pub const DXGI_MODE_DESC = extern struct {
    width: UINT,
    height: UINT,
    refresh_rate: DXGI_RATIONAL = .{},
    format: UINT = DXGI_FORMAT_B8G8R8A8_UNORM,
    scanline_ordering: UINT = 0,
    scaling: UINT = 0,
};

pub const DXGI_SWAP_CHAIN_DESC = extern struct {
    buffer_desc: DXGI_MODE_DESC,
    sample_desc: DXGI_SAMPLE_DESC = .{},
    buffer_usage: UINT = DXGI_USAGE_RENDER_TARGET_OUTPUT,
    buffer_count: UINT = 1,
    output_window: *anyopaque,
    windowed: BOOL = 1,
    swap_effect: UINT = DXGI_SWAP_EFFECT_DISCARD,
    flags: UINT = 0,
};

pub const DXGI_FORMAT_B8G8R8A8_UNORM: UINT = 87;
pub const DXGI_USAGE_RENDER_TARGET_OUTPUT: UINT = 0x00000020;
pub const DXGI_SWAP_EFFECT_DISCARD: UINT = 0;
pub const D3D_DRIVER_TYPE_HARDWARE: c_int = 1;
pub const D3D_FEATURE_LEVEL_11_0: c_int = 0xb000;
pub const D3D11_SDK_VERSION: UINT = 7;

pub extern "d3d11" fn D3D11CreateDeviceAndSwapChain(
    pAdapter: ?*anyopaque,
    DriverType: c_int,
    Software: HMODULE,
    Flags: UINT,
    pFeatureLevels: ?[*]const c_int,
    FeatureLevels: UINT,
    SDKVersion: UINT,
    pSwapChainDesc: *const DXGI_SWAP_CHAIN_DESC,
    ppSwapChain: ?*?*IDXGISwapChain,
    ppDevice: ?*?*ID3D11Device,
    pFeatureLevel: ?*c_int,
    ppImmediateContext: ?*?*ID3D11DeviceContext,
) callconv(.winapi) HRESULT;