extends Node
class_name TooltipSpawner

@export var follow_mouse := true
var _tooltip: Control
var _owner_ctrl: Control
var _overlay_root: CanvasItem
var _highlight_token = null
var _coin_mgr: Node = null
var _connected_refresh := false

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
	# Cache CoinManager reference if available
	_coin_mgr = get_node_or_null("/root/coinManager")

func _process(_dt: float) -> void:
	if follow_mouse and is_instance_valid(_tooltip):
		_position_tooltip()

func _on_entered() -> void:
	var data = null
	if _owner_ctrl != null and _owner_ctrl.has_meta("token_data"):
		data = _owner_ctrl.get_meta("token_data")
	if data == null:
		_highlight_token = null
		return
	if _overlay_root == null:
		_overlay_root = get_tree().current_scene
	if _overlay_root == null:
		return
	if is_instance_valid(_tooltip):
		_tooltip.queue_free()
		_tooltip = null

	var tooltip_node: Control = null
	var is_token := data is TokenLootData
	var is_artifact := data is ArtifactData

	if is_artifact:
		tooltip_node = ArtifactTooltipView.new()
	elif is_token:
		tooltip_node = TokenTooltipView.new()
	else:
		return

	if tooltip_node is CanvasItem:
		(tooltip_node as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if is_token and tooltip_node is TokenTooltipView:
		var base_only := false
		if _owner_ctrl != null and _owner_ctrl.has_meta("tooltip_base_only"):
			base_only = bool(_owner_ctrl.get_meta("tooltip_base_only"))
		(tooltip_node as TokenTooltipView).base_only = base_only

	_tooltip = tooltip_node
	_overlay_root.add_child(_tooltip)
	if _tooltip.has_method("set_data"):
		_tooltip.call("set_data", data)
	_tooltip.visible = true
	_position_tooltip()

	if is_token:
		_highlight_token = data
		if _coin_mgr == null:
			_coin_mgr = get_node_or_null("/root/coinManager")
		if _coin_mgr != null and _coin_mgr.has_method("start_effect_highlight_for_token"):
			_coin_mgr.call("start_effect_highlight_for_token", data)
			# If the spin is still in progress, keep the highlight in sync as effects register.
			_connect_highlight_refresh()
	else:
		_highlight_token = null

func _on_exited() -> void:
	_disconnect_highlight_refresh()
	if _coin_mgr == null:
		_coin_mgr = get_node_or_null("/root/coinManager")
	if _coin_mgr != null and _coin_mgr.has_method("stop_effect_highlight_for_token") and _highlight_token != null:
		_coin_mgr.call("stop_effect_highlight_for_token", _highlight_token)
	_highlight_token = null
	if is_instance_valid(_tooltip):
		_tooltip.queue_free()
		_tooltip = null

func _connect_highlight_refresh() -> void:
	if _connected_refresh:
		return
	if _coin_mgr == null:
		return
	# Refresh on each applied step (helps while spin is ongoing)
	if _coin_mgr.has_signal("token_step_applied"):
		_coin_mgr.connect("token_step_applied", Callable(self, "_refresh_highlight_if_hovering"))
		_connected_refresh = true
	# Also refresh when a token value is shown due to resync/replace
	if _coin_mgr.has_signal("token_value_shown") and not _coin_mgr.is_connected("token_value_shown", Callable(self, "_refresh_highlight_if_hovering")):
		_coin_mgr.connect("token_value_shown", Callable(self, "_refresh_highlight_if_hovering"))
	# Ensure final refresh when totals are ready
	if _coin_mgr.has_signal("spin_totals_ready") and not _coin_mgr.is_connected("spin_totals_ready", Callable(self, "_refresh_highlight_if_hovering")):
		_coin_mgr.connect("spin_totals_ready", Callable(self, "_refresh_highlight_if_hovering"))

func _disconnect_highlight_refresh() -> void:
	if not _connected_refresh:
		return
	if _coin_mgr == null:
		_coin_mgr = get_node_or_null("/root/coinManager")
	if _coin_mgr != null:
		if _coin_mgr.has_signal("token_step_applied") and _coin_mgr.is_connected("token_step_applied", Callable(self, "_refresh_highlight_if_hovering")):
			_coin_mgr.disconnect("token_step_applied", Callable(self, "_refresh_highlight_if_hovering"))
		if _coin_mgr.has_signal("token_value_shown") and _coin_mgr.is_connected("token_value_shown", Callable(self, "_refresh_highlight_if_hovering")):
			_coin_mgr.disconnect("token_value_shown", Callable(self, "_refresh_highlight_if_hovering"))
		if _coin_mgr.has_signal("spin_totals_ready") and _coin_mgr.is_connected("spin_totals_ready", Callable(self, "_refresh_highlight_if_hovering")):
			_coin_mgr.disconnect("spin_totals_ready", Callable(self, "_refresh_highlight_if_hovering"))
	_connected_refresh = false

func _refresh_highlight_if_hovering(_a = null, _b = null, _c = null, _d = null, _e = null) -> void:
	# Called during spin as effects register; rebuild the highlight set if still hovering.
	if _highlight_token == null or _coin_mgr == null:
		return
	if _coin_mgr.has_method("start_effect_highlight_for_token"):
		_coin_mgr.call("start_effect_highlight_for_token", _highlight_token)

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
	var sz: Vector2 = _tooltip.get_combined_minimum_size()
	if sz == Vector2.ZERO:
		sz = _tooltip.size
	pos = _tooltip.position
	if pos.x + sz.x > vp_rect.size.x - 6.0:
		pos.x = vp_rect.size.x - sz.x - 6.0
	if pos.y + sz.y > vp_rect.size.y - 6.0:
		pos.y = vp_rect.size.y - sz.y - 6.0
	_tooltip.position = Vector2(floor(pos.x), floor(pos.y))
