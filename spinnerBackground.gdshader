shader_type canvas_item;

uniform float rim_size = 3.0;         // edge shading thickness
uniform float rim_strength = 0.05;     // how dark the rim is
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear;

void fragment() {
    vec2 size_px = vec2(textureSize(SCREEN_TEXTURE, 0));
    vec2 uv_px = UV * size_px;

    // --- base color with subtle vertical gradient ---
    float vertical_shade = mix(0.04, -0.04, UV.y);
    vec3 base = vec3(0.90, 0.85, 0.75) + vertical_shade;

    // --- inner rim shading ---
    float edge_dist = min(min(uv_px.x, size_px.x - uv_px.x),
                          min(uv_px.y, size_px.y - uv_px.y));
    float edge_dark = smoothstep(rim_size, 0.0, edge_dist);
    base *= (1.0 - edge_dark * rim_strength);

    COLOR = vec4(base, 0.75);
}
