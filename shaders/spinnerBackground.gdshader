// wave_clip_pixelated.shader
shader_type canvas_item;

// dimensions + clock (set from GDScript)
uniform vec2   resolution;
uniform float  time;

// base fill color (Inspector shows a color-picker)
uniform vec4   panel_color      = vec4(0.2, 0.4, 0.8, 1.0);

// top‐edge wave
uniform float  clip_height      = 30.0;
uniform float  wave_amp         = 15.0;
uniform float  wave_freq        = 3.0;
uniform float  wave_speed       = 1.5;

// ripple on demand
uniform vec2   ripple_center    = vec2(0.5, 0.5);
uniform float  ripple_start     = -100.0;
uniform float  ripple_speed     = 400.0;
uniform float  ripple_amp       = 50.0;

// pixelation controls
uniform float  pixel_size       = 0.02;  // in UV‐space (bigger = chunkier)
uniform float  color_steps      = 6.0;   // number of discrete color bands

void fragment() {
    // 1. Snap UV to a pixel grid
    vec2 pix_uv = floor(UV / pixel_size) * pixel_size;

    // 2. Compute pixel‐space coords
    vec2 uv_px = pix_uv * resolution;

    // 3. Top wavy clip line (measured down from top)
    float base_y   = clip_height;
    float wave_off = sin((uv_px.x / resolution.x) * PI * wave_freq
                        + time * wave_speed)
                   * wave_amp;
    float clip_line = base_y + wave_off;

    // 4. Discard everything above the wavy line
    if (uv_px.y < clip_line) {
        discard;
    }

    // 5. Start with flat panel color
    vec4 col = panel_color;

    // 6. Tiny “breathing” wave tint
    float tiny = sin((uv_px.x + uv_px.y)*0.02 + time*2.0) * 2.0;
    col.rgb += tiny * 0.02;

    // 7. Big ripple on demand
    float t = time - ripple_start;
    if (t >= 0.0) {
        float d = distance(uv_px, ripple_center * resolution);
        float bump = sin(d - t * ripple_speed)
                   * ripple_amp
                   / (d * 0.1 + 1.0);
        bump *= max(1.0 - t * 0.5, 0.0);
        col.rgb += bump / 255.0;
    }

    // 8. Quantize final color into discrete bands
    col.rgb = floor(col.rgb * color_steps) / color_steps;

    COLOR = col;
}