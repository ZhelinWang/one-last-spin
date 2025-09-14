shader_type canvas_item;

uniform vec4 color_a : source_color = vec4(0.2, 0.2, 0.25, 0.4); // top-left
uniform vec4 color_b : source_color = vec4(0.15, 0.15, 0.2, 0.4); // bottom-right
uniform float swirl_strength = 2.0;
uniform float swirl_speed = 0.02;
uniform float swirl_opacity = 0.1;

void fragment() {
    // Base gradient
    vec4 grad = mix(color_a, color_b, UV.y);

    // Swirl overlay (very faint, adds motion)
    vec2 center = UV - 0.5;
    float angle = atan(center.y, center.x);
    float radius = length(center);

    float swirl = sin(angle * swirl_strength + TIME * swirl_speed) * 0.5 + 0.5;
    swirl *= smoothstep(0.0, 0.5, radius);  // fade near center
    swirl *= swirl_opacity;

    vec4 swirl_color = vec4(vec3(swirl), swirl);

    COLOR = grad + swirl_color;
}
