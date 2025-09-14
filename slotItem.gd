extends Button

@export var slot_size: Vector2i = Vector2i(128, 128)
@export var max_skew_x: float   = 0.5
@export var max_skew_y: float   = 0.75

var _data: TokenLootData
var _hovering: bool = false

@export var data: TokenLootData:
	get: return _data
	set(value):
		_data = value
		if is_inside_tree():
			_render()

@onready var _icon:       TextureRect     = $icon
@onready var _icon_mat:   ShaderMaterial  = ShaderMaterial.new()

func _ready() -> void:
	#— your existing layout / icon setup
	flat = true
	for m in ["left","right","top","bottom"]:
		add_theme_constant_override("content_margin_%s" % m, 0)
	custom_minimum_size = Vector2(slot_size)

	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left    = 0
	_icon.offset_top     = 0
	_icon.offset_right   = 0
	_icon.offset_bottom  = 0
	_icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	#— assign our skew shader to the icon
	_icon_mat.shader   = preload("res://shaders/slotItemParallax.gdshader")
	_icon.material    = _icon_mat

	#— ensure the shader knows which texture to skew
	if _icon.texture:
		_icon_mat.set_shader_parameter("albedo_tex", _icon.texture)

	#— initial render if you've already set data in the inspector
	if _data:
		_render()

	#— hover setup
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func _render() -> void:
	if _data == null:
		return
	_icon.texture = _data.icon
	#_icon.modulate = _data.get_color()
	_icon_mat.set_shader_parameter("albedo_tex", _data.icon)

func _process(delta: float) -> void:
	if not _hovering:
		return

	var mpos = get_local_mouse_position()
	var nx   = (mpos.x / size.x - 0.5) * 2.0
	var ny   = (mpos.y / size.y - 0.5) * 2.0

	_icon_mat.set_shader_parameter("skew_x", -nx * max_skew_x)
	_icon_mat.set_shader_parameter("skew_y",  ny * max_skew_y)

func _on_mouse_entered() -> void:
	_hovering = true

func _on_mouse_exited() -> void:
	_hovering = false

	# Guards
	if _icon_mat == null or !is_instance_valid(_icon_mat):
		return
	if !(_icon_mat is ShaderMaterial):
		return
	var sm := _icon_mat as ShaderMaterial
	if sm.shader == null:
		return
	# Optional: verify uniforms exist (avoid intermittent nulls)
	var has_x := true
	var has_y := true
	if sm.shader.has_method("get_uniform_list"):
		var names := {}
		for u in sm.shader.get_uniform_list():
			names[u.name] = true
		has_x = names.has("skew_x")
		has_y = names.has("skew_y")

	var tween := create_tween().set_parallel(true)

	if has_x:
		var t1 := tween.tween_property(sm, "shader_parameter/skew_x", 0.0, 0.2)
		if t1 != null: t1.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if has_y:
		var t2 := tween.tween_property(sm, "shader_parameter/skew_y", 0.0, 0.2)
		if t2 != null: t2.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
#func _on_mouse_entered() -> void:
	#print("mouse entered slot")
	#customTooltip.TooltipPopup(null, null)
#
#func _on_mouse_exited() -> void:
	#print("mouse exited slot")
	#customTooltip.HideTooltipPopup()
