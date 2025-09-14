shader_type canvas_item;

uniform float speed = 0.1;
uniform float swirl_strength = 2.5;
uniform float scale = 6.0;
uniform float center_softness = 0.6;

uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;

uniform float pixel_size = 0.01; // Size of pixel blocks (smaller = finer)

void fragment() {
    // Snap UV to pixel grid
    vec2 snapped_uv = floor(UV / pixel_size) * pixel_size;

    // Centered and scaled UV
    vec2 uv = (snapped_uv - vec2(0.5)) * scale;

    // Polar coordinates
    float r = length(uv);
    float angle = atan(uv.y, uv.x);

    // Swirl animation
    float swirl = angle + r * swirl_strength + TIME * speed * 0.25;

    // Wave pattern
    float wave = sin(swirl);

    // Soften center
    float softness = smoothstep(0.0, center_softness, r);
    wave *= softness;

    // Normalize wave to [0, 1]
    wave = (wave + 1.0) * 0.5;

    // Quantize wave to discrete steps for pixel feel
    float steps = 6.0; // Number of color bands
    wave = floor(wave * steps) / steps;

    // Blend colors
    COLOR = mix(color_a, color_b, wave);
}