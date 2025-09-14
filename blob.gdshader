shader_type canvas_item;
render_mode unshaded, blend_mix;

// Overall opacity of the dark blobs
uniform float base_alpha = 0.55;      // 0..1
// Pixel scale of the pattern (bigger => chunkier)
uniform float tile_px = 36.0;         // pixels per cell
// Animation speed in pixels per second
uniform float flow_speed_px = 8.0;
// Threshold and edge for blob coverage
uniform float threshold = 0.45;       // 0..1
uniform float edge_feather = 0.0;     // in 0..1 (set 0 for hard pixel edges)

// Simple hash and value noise
float hash21(vec2 p){
    p = fract(p*vec2(234.34, 435.345));
    p += dot(p, p+34.345);
    return fract(p.x*p.y);
}
float value_noise(vec2 p){
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    vec2 u = f*f*(3.0-2.0*f);
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}

void fragment() {
    // Screen pixel coordinates
    float SW = 1.0 / SCREEN_PIXEL_SIZE.x;
    float SH = 1.0 / SCREEN_PIXEL_SIZE.y;
    vec2 screen_px = vec2(UV.x * SW, UV.y * SH);

    // Pixelate position so edges stay chunky
    float s = max(tile_px, 1.0);
    vec2 p = floor(screen_px / s) * (1.0 / s);

    // Flow across time (in pixels/sec)
    float t = TIME * (flow_speed_px / max(tile_px, 1.0));
    vec2 flow = vec2(t, -0.7 * t);

    // 2-octave value noise
    float n  = value_noise((screen_px / tile_px) + flow);
    n = 0.7*n + 0.3*value_noise((screen_px / (tile_px*0.5)) - flow*0.6);

    // Threshold to blobs
    float th = clamp(threshold, 0.0, 1.0);
    float a;
    if (edge_feather <= 0.0) {
        a = step(th, n);
    } else {
        float e = clamp(edge_feather, 0.0, 0.5);
        a = smoothstep(th - e, th + e, n);
    }

    COLOR = vec4(0.0, 0.0, 0.0, a * base_alpha);
}