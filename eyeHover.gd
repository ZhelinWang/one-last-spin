extends TextureRect

@onready var spin_root: Node = _resolve_spin_root()
var _preview_locked: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_gui_signals_ready()

func _gui_signals_ready() -> void:
	if not is_connected("mouse_entered", Callable(self, "_on_hover_entered")):
		mouse_entered.connect(_on_hover_entered)
	if not is_connected("mouse_exited", Callable(self, "_on_hover_exited")):
		mouse_exited.connect(_on_hover_exited)

func _resolve_spin_root() -> Node:
	if get_tree() == null:
		return null
	var scene := get_tree().current_scene
	if scene != null:
		if scene.has_node("%spinRoot"):
			return scene.get_node("%spinRoot")
		var sr := scene.find_child("spinRoot", true, false)
		if sr != null:
			return sr
	var root := get_tree().root
	if root != null:
		if root.has_node("%spinRoot"):
			return root.get_node("%spinRoot")
		var sr2 := root.find_child("spinRoot", true, false)
		if sr2 != null:
			return sr2
	return null

func _on_hover_entered() -> void:
	if spin_root == null or !is_instance_valid(spin_root):
		spin_root = _resolve_spin_root()
	if spin_root != null and spin_root.has_method("show_base_preview"):
		spin_root.call("show_base_preview")

func _on_hover_exited() -> void:
	if spin_root != null and spin_root.has_method("hide_base_preview"):
		spin_root.call("hide_base_preview")

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_toggle_preview_lock()
		accept_event()

func _toggle_preview_lock() -> void:
	_preview_locked = not _preview_locked
	if spin_root == null or !is_instance_valid(spin_root):
		spin_root = _resolve_spin_root()
	if spin_root == null:
		return
	if spin_root.has_method("set_base_preview_lock"):
		spin_root.call("set_base_preview_lock", _preview_locked)
