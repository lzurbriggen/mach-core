struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
    @location(0) fragUV: vec2<f32>,
    @location(1) color: vec4<f32>,
}

@vertex 
fn vertex_main(
    @location(0) pos: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) color: vec4<f32>,
) -> VertexOut {
    var output: VertexOut;
    output.position_clip = vec4<f32>(pos, 0.0, 1.0);
    output.fragUV = uv;
    output.color = color;
    return output;
}

@fragment
fn frag_main(
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
) -> @location(0) vec4<f32> {
    return color;
}
