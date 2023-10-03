@binding(0) @group(0) var<uniform> ubos : array<mat4x4<f32>, 16>;

struct VertexOutput {
  @builtin(position) position_clip: vec4<f32>,
  @location(0) fragUV: vec2<f32>,
  @location(1) fragPosition: vec4<f32>,
  @location(2) color: vec4<f32>,
};

@vertex
fn vertex_main(@builtin(instance_index) instanceIdx: u32, @location(0) position: vec4<f32>, @location(1) uv: vec2<f32>, @location(2) color: vec4<f32>) -> VertexOutput {
    var output: VertexOutput;
    output.position_clip = ubos[instanceIdx] * position;
    output.fragUV = uv;
    output.fragPosition = 0.5 * (position + vec4<f32>(1.0, 1.0, 1.0, 1.0));
    output.color = color;
    return output;
}

@fragment
fn frag_main(
    @location(0) fragUV: vec2<f32>,
    @location(1) fragPosition: vec4<f32>,
    @location(2) color: vec4<f32>
) -> @location(0) vec4<f32> {
    return mix(color, vec4<f32>(fragUV, 0.0, 1.0), 0.1);
}