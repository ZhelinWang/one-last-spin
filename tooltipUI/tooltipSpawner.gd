extends Node
class_name TooltipSpawner

@export var follow_mouse := true
var _tooltip: TokenTooltipView
var _owner_ctrl: Control
var _overlay_root: CanvasItem

func _ready() -> void:
	_owner_ctrl = get_parent() as Control
	if _owner_ctrl == null:
		queue_free()
		return
	_owner_ctrl.mouse_entered.connect(_on_entered)
	_owner_ctrl.mouse_exited.connect(_on_exited)
	_owner_ctrl.focus_exited.connect(_on_exited)
	_overlay_root = get_tree().current_scene
	set_process(true)

func _process(_dt: float) -> void:
	if follow_mouse and is_instance_valid(_tooltip):
		_position_tooltip()

func _on_entered() -> void:
	var data: TokenLootData = null
	if _owner_ctrl != null:
		data = _owner_ctrl.get_meta("token_data") as TokenLootData
	if data == null:
		return
	if _overlay_root == null:
		_overlay_root = get_tree().current_scene
	if _overlay_root == null:
		return
	if is_instance_valid(_tooltip):
		_tooltip.queue_free()
	_tooltip = TokenTooltipView.new()
	_tooltip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay_root.add_child(_tooltip)
	_tooltip.set_data(data)
	_tooltip.visible = true
	_position_tooltip()

func _on_exited() -> void:
	if is_instance_valid(_tooltip):
		_tooltip.queue_free()
		_tooltip = null

func _position_tooltip() -> void:
	if not is_instance_valid(_tooltip):
		return
	var vp := get_viewport()
	if vp == null:
		return
	var mouse := vp.get_mouse_position()
	var margin := Vector2(14, 10)
	var pos := mouse + margin
	# Pixel snap: round to integers for a crisp arcade look
	pos.x = floor(pos.x)
	pos.y = floor(pos.y)
	_tooltip.position = pos
	_tooltip.reset_size()

	# Clamp to viewport
	var vp_rect := vp.get_visible_rect()
	var size := _tooltip.get_combined_minimum_size()
	if size == Vector2.ZERO:
		size = _tooltip.size
	pos = _tooltip.position
	if pos.x + size.x > vp_rect.size.x - 6.0:
		pos.x = vp_rect.size.x - size.x - 6.0
	if pos.y + size.y > vp_rect.size.y - 6.0:
		pos.y = vp_rect.size.y - size.y - 6.0
	_tooltip.position = Vector2(floor(pos.x), floor(pos.y))
