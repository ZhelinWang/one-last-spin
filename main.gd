# Main.gd
extends Control
#
#@onready var spinner: Control = %spinRoot
#@onready var result_label: RichTextLabel = %valueLabel
#
func _ready() -> void:
	add_vignette_to_ui(self)

func add_vignette_to_ui(root: Control) -> void:
	if root.get_node_or_null("VignetteOverlay") != null:
		return
	var overlay := ColorRect.new()
	overlay.name = "VignetteOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0) # color/alpha comes from shader
	overlay.z_index = 50              # above background, below modal overlays

	var sh := Shader.new()
	sh.code = """
	shader_type canvas_item;

	// Edge thickness and softness in pixels
	uniform float width_px     : hint_range(0.0, 512.0) = 50.0;
	uniform float softness_px  : hint_range(0.1, 512.0) = 512.0;
	uniform float intensity    : hint_range(0.0, 1.0)   = 0.05;
	uniform vec4  tint : source_color = vec4(0.0, 0.0, 0.0, 1.0); // edge color
	// Per-edge enable (left, right, top, bottom)
	uniform vec4 edges = vec4(1.0, 1.0, 1.0, 1.0);

	void fragment() {
		// Screen size in pixels and current pixel coords
		vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
		vec2 px = SCREEN_UV * screen_size;

		float distL = px.x;
		float distR = screen_size.x - px.x;
		float distT = px.y;
		float distB = screen_size.y - px.y;

		// 1 - smoothstep => 1 at edge, 0 after width+softness
		float l = edges.x * (1.0 - smoothstep(width_px, width_px + softness_px, distL));
		float r = edges.y * (1.0 - smoothstep(width_px, width_px + softness_px, distR));
		float t = edges.z * (1.0 - smoothstep(width_px, width_px + softness_px, distT));
		float b = edges.w * (1.0 - smoothstep(width_px, width_px + softness_px, distB));

		// Use max so corners aren’t darker than edges
		float edge_alpha = max(max(l, r), max(t, b));

		COLOR = vec4(tint.rgb, tint.a * edge_alpha * intensity);
	}
	"""

	var mat := ShaderMaterial.new()
	mat.shader = sh
	overlay.material = mat

	root.add_child(overlay)
