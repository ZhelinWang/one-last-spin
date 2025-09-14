shader_type canvas_item;
render_mode unshaded, blend_mix;

// Crisp alpha binarization
uniform float alpha_threshold = 0.5;

// Outline radius in texels (1 = 1px, 2 = 2px)
uniform float outline_radius = 2.0;

// Outline style
uniform bool use_diagonals = true; // true => 8-neighbor (continuous corners)

// Colors
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0); // black
uniform vec4 fill_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0); // white target
uniform float fill_mix = 0.0;  // 0 = keep original color, 1 = force white like "+1"

// Hard pixel shadow
uniform bool  shadow_enabled = true;
uniform vec2  shadow_offset_px = vec2(2.0, 2.0);
uniform float shadow_alpha = 1.0;

void fragment() {
    vec4 tint = COLOR;
    vec4 tex  = texture(TEXTURE, UV);

    // Binarize glyph (remove grey fringes)
    float src = step(alpha_threshold, tex.a);

    // One-texel step
    vec2 ts = TEXTURE_PIXEL_SIZE;

    // Ring r=1, 4-neighbor
    float nL = step(alpha_threshold, texture(TEXTURE, UV + vec2(-ts.x, 0.0)).a);
    float nR = step(alpha_threshold, texture(TEXTURE, UV + vec2( ts.x, 0.0)).a);
    float nU = step(alpha_threshold, texture(TEXTURE, UV + vec2( 0.0, -ts.y)).a);
    float nD = step(alpha_threshold, texture(TEXTURE, UV + vec2( 0.0,  ts.y)).a);
    float n_any = max(max(nL, nR), max(nU, nD));

    // Add diagonals for continuous outline (8-neighbor)
    if (use_diagonals) {
        float nUL = step(alpha_threshold, texture(TEXTURE, UV + vec2(-ts.x, -ts.y)).a);
        float nUR = step(alpha_threshold, texture(TEXTURE, UV + vec2( ts.x, -ts.y)).a);
        float nDL = step(alpha_threshold, texture(TEXTURE, UV + vec2(-ts.x,  ts.y)).a);
        float nDR = step(alpha_threshold, texture(TEXTURE, UV + vec2( ts.x,  ts.y)).a);
        n_any = max(n_any, max(max(nUL, nUR), max(nDL, nDR)));
    }

    // Optional ring r=2 for a thicker sticker
    float r = floor(outline_radius + 0.5);
    if (r >= 2.0) {
        // Axis 2px
        float aL2 = step(alpha_threshold, texture(TEXTURE, UV + vec2(-2.0 * ts.x, 0.0)).a);
        float aR2 = step(alpha_threshold, texture(TEXTURE, UV + vec2( 2.0 * ts.x, 0.0)).a);
        float aU2 = step(alpha_threshold, texture(TEXTURE, UV + vec2( 0.0, -2.0 * ts.y)).a);
        float aD2 = step(alpha_threshold, texture(TEXTURE, UV + vec2( 0.0,  2.0 * ts.y)).a);
        float n2 = max(max(aL2, aR2), max(aU2, aD2));

        if (use_diagonals) {
            // Diagonals and "knight" offsets to make a solid 2px ring
            float d11 = step(alpha_threshold, texture(TEXTURE, UV + vec2( 2.0 * ts.x,  2.0 * ts.y)).a);
            float d1n1= step(alpha_threshold, texture(TEXTURE, UV + vec2( 2.0 * ts.x, -2.0 * ts.y)).a);
            float dn11= step(alpha_threshold, texture(TEXTURE, UV + vec2(-2.0 * ts.x,  2.0 * ts.y)).a);
            float dn1n1=step(alpha_threshold, texture(TEXTURE, UV + vec2(-2.0 * ts.x, -2.0 * ts.y)).a);

            float k21 = step(alpha_threshold, texture(TEXTURE, UV + vec2( 2.0 * ts.x,  ts.y)).a);
            float k2n1= step(alpha_threshold, texture(TEXTURE, UV + vec2( 2.0 * ts.x, -ts.y)).a);
            float k12 = step(alpha_threshold, texture(TEXTURE, UV + vec2( ts.x,  2.0 * ts.y)).a);
            float kn12= step(alpha_threshold, texture(TEXTURE, UV + vec2(-ts.x,  2.0 * ts.y)).a);
            float kn21= step(alpha_threshold, texture(TEXTURE, UV + vec2(-2.0 * ts.x,  ts.y)).a);
            float kn2n1=step(alpha_threshold, texture(TEXTURE, UV + vec2(-2.0 * ts.x, -ts.y)).a);
            float k1n2= step(alpha_threshold, texture(TEXTURE, UV + vec2( ts.x, -2.0 * ts.y)).a);
            float kn1n2=step(alpha_threshold, texture(TEXTURE, UV + vec2(-ts.x, -2.0 * ts.y)).a);

            float n2d = max(max(max(d11, d1n1), max(dn11, dn1n1)),
                            max(max(max(k21, k2n1), max(k12, k1n2)),
                                max(max(kn12, kn21), max(kn2n1, kn1n2))));
            n2 = max(n2, n2d);
        }
        n_any = max(n_any, n2);
    }

    // Outline (outside only)
    bool is_outline = (src < 0.5) && (n_any > 0.5);

    // Inner edge (inside but touching empty at r=1)
    float n1_all = min(min(nL, nR), min(nU, nD));
    if (use_diagonals) {
        float nUL = step(alpha_threshold, texture(TEXTURE, UV + vec2(-ts.x, -ts.y)).a);
        float nUR = step(alpha_threshold, texture(TEXTURE, UV + vec2( ts.x, -ts.y)).a);
        float nDL = step(alpha_threshold, texture(TEXTURE, UV + vec2(-ts.x,  ts.y)).a);
        float nDR = step(alpha_threshold, texture(TEXTURE, UV + vec2( ts.x,  ts.y)).a);
        n1_all = min(n1_all, min(min(nUL, nUR), min(nDL, nDR)));
    }
    bool is_inner = (src > 0.5) && (n1_all < 0.5);

    // Shadow
    bool shadow_hit = false;
    if (shadow_enabled) {
        vec2 soff = TEXTURE_PIXEL_SIZE * shadow_offset_px;
        float s_src = step(alpha_threshold, texture(TEXTURE, UV - soff).a);
        shadow_hit = (src < 0.5) && !is_outline && (s_src > 0.5);
    }

    // Preserve original text color; allow optional push toward white via fill_mix
    vec3 preserved = tex.rgb * tint.rgb;
    vec3 base_fill = mix(preserved, fill_color.rgb, clamp(fill_mix, 0.0, 1.0));

    // Priority: shadow < outline < inner < fill
    vec4 col = vec4(0.0);
    if (shadow_hit) {
        col = vec4(0.0, 0.0, 0.0, shadow_alpha);
    }
    if (is_outline) {
        col = vec4(outline_color.rgb, outline_color.a);
    }
    if (is_inner) {
        col = vec4(fill_color.rgb, 1.0); // crisp white inner edge
    }
    if (src > 0.5) {
        col = vec4(base_fill, 1.0);
    }

    COLOR = col;
}