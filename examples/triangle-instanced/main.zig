const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub const App = @This();

title_timer: core.Timer,
pipeline: *gpu.RenderPipeline,

pub fn init(app: *App) !void {
    try core.init(.{});

    const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attributes = &[_]gpu.VertexAttribute{
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
        },
    });

    const instance_vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .instance,
        .attributes = &[_]gpu.VertexAttribute{
            .{ .format = .float32x4, .offset = @offsetOf(Instance, "color"), .shader_location = 2 },
        },
    });

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vertex_main",
            .buffers = &.{ vertex_buffer_layout, instance_vertex_buffer_layout },
        }),
        .primitive = .{ .cull_mode = .none },
    };
    const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    app.* = .{ .title_timer = try core.Timer.start(), .pipeline = pipeline };
}

pub fn deinit(app: *App) void {
    defer core.deinit();
    app.pipeline.release();
}

const Vertex = extern struct {
    pos: @Vector(2, f32),
    uv: @Vector(2, f32),
};

const Instance = extern struct {
    color: @Vector(4, f32),
};

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            else => {},
        }
    }

    const queue = core.queue;
    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);

    const num_verts_per_instance = 3;
    const num_instances = 4;

    var vertices: [num_instances * num_verts_per_instance]Vertex = undefined;
    // stupid code, align vertices of 4 triangles next to each other
    for (0..num_instances) |i| {
        const if32 = @as(f32, @floatFromInt(i));
        const num_instances_f32 = @as(f32, @floatFromInt(num_instances));
        vertices[i * num_verts_per_instance] = Vertex{
            .pos = .{ -1.0 / num_instances_f32 + (if32 / num_instances_f32 - 0.5), -1 },
            .uv = .{ 0, 1 },
        };
        vertices[i * num_verts_per_instance + 1] = Vertex{
            .pos = .{ 1.0 / num_instances_f32 + (if32 / num_instances_f32 - 0.5), 1 },
            .uv = .{ 1, 0 },
        };
        vertices[i * num_verts_per_instance + 2] = Vertex{
            .pos = .{ -1.0 / num_instances_f32 + (if32 / num_instances_f32 - 0.5), 1 },
            .uv = .{ 0, 0 },
        };
    }

    // vertex buffer
    const vertex_buffer = core.device.createBuffer(&.{
        .usage = .{ .vertex = true },
        .size = @sizeOf(Vertex) * num_verts_per_instance * num_instances,
        .mapped_at_creation = .true,
    });
    defer vertex_buffer.release();

    pass.setVertexBuffer(0, vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
    var vertex_mapped = vertex_buffer.getMappedRange(Vertex, 0, vertices.len);
    std.mem.copy(Vertex, vertex_mapped.?, &vertices);
    vertex_buffer.unmap();

    // instance vertex buffer
    var instance_data: [num_instances]Instance = undefined;
    for (0..num_instances) |i| {
        const if32 = @as(f32, @floatFromInt(i));
        const num_instances_f32 = @as(f32, @floatFromInt(num_instances));
        instance_data[i] = Instance{
            // different color per instance
            .color = .{ if32 / num_instances_f32, (1 - if32 / num_instances_f32), 0, 1 },
        };
    }
    const second_vertex_buffer = core.device.createBuffer(&.{
        .usage = .{ .vertex = true },
        .size = @sizeOf(Instance) * num_instances,
        .mapped_at_creation = .true,
    });
    defer second_vertex_buffer.release();

    pass.setVertexBuffer(1, second_vertex_buffer, 0, @sizeOf(Instance) * instance_data.len);
    var second_vertex_mapped = second_vertex_buffer.getMappedRange(Instance, 0, instance_data.len);
    std.mem.copy(Instance, second_vertex_mapped.?, &instance_data);
    second_vertex_buffer.unmap();

    // index buffer
    const index_data = [_]u16{ 0, 1, 2 };
    const index_buffer = core.device.createBuffer(&.{
        .usage = .{ .index = true, .copy_dst = true },
        // needs to be a multiple of 4
        .size = (index_data.len + 1) * @sizeOf(u16),
        .mapped_at_creation = .true,
    });
    defer index_buffer.release();

    pass.setIndexBuffer(index_buffer, .uint16, 0, @sizeOf(u16) * index_data.len);
    var index_mapping = index_buffer.getMappedRange(u16, 0, index_data.len).?;
    std.mem.copy(u16, index_mapping[0..index_data.len], &index_data);
    index_buffer.unmap();

    // indirect buffer
    const indirect_data = [_]u32{
        num_verts_per_instance, // verts per instance
        num_instances, // num of instances
        0, // firstIndex
        0, // baseVertex
        0, // firstInstance
    };
    const indirect_buffer = core.device.createBuffer(&.{
        .usage = .{ .indirect = true, .copy_dst = true },
        .size = indirect_data.len * @sizeOf(u32),
        .mapped_at_creation = .true,
    });
    var indirect_mapping = indirect_buffer.getMappedRange(u32, 0, indirect_data.len).?;
    std.mem.copy(u32, indirect_mapping[0..indirect_data.len], &indirect_data);
    indirect_buffer.unmap();
    defer indirect_buffer.release();

    pass.drawIndexedIndirect(indirect_buffer, 0);

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.present();
    back_buffer_view.release();

    // update the window title every second
    if (app.title_timer.read() >= 1.0) {
        app.title_timer.reset();
        try core.printTitle("Triangle [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }

    return false;
}
