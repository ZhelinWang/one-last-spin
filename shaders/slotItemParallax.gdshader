shader_type canvas_item;

// no hint on our texture uniform—Godot 4 will let us set it manually
uniform sampler2D albedo_tex;

// skew amounts, in pixels per UV‐unit
uniform float skew_x : hint_range(-1.0, 1.0) = 0.0;
uniform float skew_y : hint_range(-1.0, 1.0) = 0.0;

void vertex() {
    // get full texture size
    ivec2 tex_px = textureSize(albedo_tex, 0);
    vec2  ts     = vec2(tex_px);

    // (UV - 0.5)*2 => [-1,1], then scale by skew*pixel_count
    vec2 off;
    off.x = (UV.y - 0.5) * skew_x * ts.x;
    off.y = (UV.x - 0.5) * skew_y * ts.y;

    VERTEX += off;
}