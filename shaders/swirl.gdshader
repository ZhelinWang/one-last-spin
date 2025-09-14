shader_type canvas_item;

uniform float speed = 0.001;
uniform float swirl_strength = 4.0;
uniform float scale = 8.0;
uniform float center_softness = 0.4;

uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;

uniform float pixel_size = 0.015; // Controls pixel block size
uniform float color_steps = 6.0;  // Number of color bands

void fragment() {
    // Snap UV to pixel grid
    vec2 snapped_uv = floor(UV / pixel_size) * pixel_size;

    // Centered and scaled UV
    vec2 uv = (snapped_uv - vec2(0.5)) * scale;

    // Polar coordinates
    float r = length(uv);
    float angle = atan(uv.y, uv.x);

    // Swirl animation with chaotic layering
    float swirl = angle + r * swirl_strength + TIME * speed;
    float pulse = sin(swirl * 3.0 + sin(r * 12.0 + TIME * 0.25));

    // Sharpen and distort wave
    float wave = pow(abs(pulse), 5.0) * sign(pulse);
    wave *= smoothstep(0.0, center_softness, r);
    wave *= smoothstep(1.2, 0.3, r);

    // Normalize to [0, 1]
    wave = (wave + 1.0) * 0.5;

    // Quantize wave for pixel-style banding
    float bands = floor(wave * color_steps) / color_steps;

    // Final color blend with exaggerated contrast
    vec4 swirl_color = mix(color_a, color_b, bands);
    swirl_color.rgb += bands * 0.15; // Glow-like punch

    COLOR = swirl_color;
}