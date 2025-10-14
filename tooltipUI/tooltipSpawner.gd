extends Node
class_name TooltipSpawner

@export var follow_mouse := true
var _tooltip: Control
var _owner_ctrl: Control
var _overlay_root: CanvasItem
var _highlight_token = null
var _coin_mgr: Node = null
var _connected_refresh := false
var _dim_locked := false

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
	# Keep prior dim lock across hover enter; do not reset here
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

	var apply_active_dim := false
	var apply_passive_dim := false
	var board_info := _resolve_board_slot_info()
	var board_dim_all := false
	if board_info.get("is_board", false):
		var idx := int(board_info.get("index", -1))
		var center_idx := int(board_info.get("center", -1))
		if idx != -1 and center_idx >= 0 and idx != center_idx:
			var diff = abs(idx - center_idx)
			if diff > 2:
				board_dim_all = true

	if is_token and tooltip_node is TokenTooltipView:
		var base_only := false
		if _owner_ctrl != null and _owner_ctrl.has_meta("tooltip_base_only"):
			base_only = bool(_owner_ctrl.get_meta("tooltip_base_only"))
		var dim_all := false
		if _owner_ctrl != null and _owner_ctrl.has_meta("tooltip_dim_all"):
			dim_all = bool(_owner_ctrl.get_meta("tooltip_dim_all"))
		elif has_meta("tooltip_dim_all"):
			dim_all = bool(get_meta("tooltip_dim_all"))
		elif _owner_ctrl != null:
			var parent := _owner_ctrl.get_parent()
			if parent != null and parent.name.to_lower().find("peek") != -1:
				dim_all = true
		if not dim_all:
			dim_all = board_dim_all
		(tooltip_node as TokenTooltipView).base_only = base_only
		# Apply initial dim state for triggered-but-non-winner slots (spinner only)
		var dim_now := _compute_dim_for_owner()
		if dim_now:
			_dim_locked = true
		var active_dim := dim_now or dim_all
		var tip_view := tooltip_node as TokenTooltipView
		tip_view.force_dim_active = active_dim
		tip_view.force_dim_passive = dim_all
		tip_view.dim_active_title_when_dimmed = dim_all
		tip_view.dim_passive_title_when_dimmed = dim_all
		tip_view.dim_value_when_dimmed = dim_all
		tip_view.dim_tags_when_dimmed = dim_all
		tip_view.set_dim_active(active_dim)
		tip_view.set_dim_passive(dim_all)
		tip_view.set_dim_value(dim_all)
		tip_view.set_dim_tags(dim_all)
		apply_active_dim = active_dim
		apply_passive_dim = dim_all

	_tooltip = tooltip_node
	_overlay_root.add_child(_tooltip)
	if _tooltip.has_method("set_data"):
		_tooltip.call("set_data", data)
		if is_token and tooltip_node is TokenTooltipView:
			(tooltip_node as TokenTooltipView).set_dim_active(apply_active_dim)
			(tooltip_node as TokenTooltipView).set_dim_passive(apply_passive_dim)
			(tooltip_node as TokenTooltipView).set_dim_value(apply_passive_dim)
			(tooltip_node as TokenTooltipView).set_dim_tags(apply_passive_dim)
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
	# Do not reset _dim_locked on hover exit; we recompute/clear it only when state changes
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
	# Also keep the tooltip's dim state in sync across spin phases
	if is_instance_valid(_tooltip) and _tooltip is TokenTooltipView:
		var board_info := _resolve_board_slot_info()
		var board_dim_all := false
		if board_info.get("is_board", false):
			var idx := int(board_info.get("index", -1))
			var center_idx := int(board_info.get("center", -1))
			if idx != -1 and center_idx >= 0 and idx != center_idx:
				var diff = abs(idx - center_idx)
				if diff > 2:
					board_dim_all = true
		var dim_all := false
		if _owner_ctrl != null and _owner_ctrl.has_meta("tooltip_dim_all"):
			dim_all = bool(_owner_ctrl.get_meta("tooltip_dim_all"))
		elif has_meta("tooltip_dim_all"):
			dim_all = bool(get_meta("tooltip_dim_all"))
		elif _owner_ctrl != null:
			var parent := _owner_ctrl.get_parent()
			if parent != null and parent.name.to_lower().find("peek") != -1:
				dim_all = true
		if not dim_all:
			dim_all = board_dim_all
		var dim_now := _compute_dim_for_owner()
		if dim_now:
			_dim_locked = true
		var desired_active := dim_all or dim_now or _dim_locked
		var tip_view := _tooltip as TokenTooltipView
		tip_view.force_dim_active = desired_active
		tip_view.force_dim_passive = dim_all
		tip_view.dim_active_title_when_dimmed = dim_all
		tip_view.dim_passive_title_when_dimmed = dim_all
		tip_view.dim_value_when_dimmed = dim_all
		tip_view.dim_tags_when_dimmed = dim_all
		tip_view.set_dim_active(desired_active)
		tip_view.set_dim_passive(dim_all)
		tip_view.set_dim_value(dim_all)
		tip_view.set_dim_tags(dim_all)

func _compute_dim_for_owner() -> bool:
	# Grey out Active when hovering a triggered-but-non-winner slot (±2 around center, excluding center).
	# Inventory items should not be affected (no spinRoot ancestor).
	var info := _resolve_board_slot_info()
	if not info.get("is_board", false):
		return false
	var idx := int(info.get("index", -1))
	var center_idx := int(info.get("center", -1))
	if idx == -1 or center_idx < 0 or idx == center_idx:
		return false
	return abs(idx - center_idx) <= 2

func _resolve_board_slot_info() -> Dictionary:
	var result := {
		"is_board": false,
		"index": -1,
		"center": -1
	}
	var sr: Node = _owner_ctrl
	while sr != null and sr.name != "spinRoot":
		sr = sr.get_parent()
	if sr == null:
		return result
	var slots = sr.get("slots_hbox") if (sr as Object).has_method("get") else null
	if slots == null or not (slots is Node):
		slots = sr.get_node_or_null("spinner/spinnerTilesMargin/scrollContainer/slotsHBox")
	if slots == null or not (slots is HBoxContainer):
		return result
	var kids: Array = (slots as HBoxContainer).get_children()
	# Resolve which slot this owner belongs to: walk up until the direct child of slots_hbox
	var owner_node: Node = _owner_ctrl
	var slot_ancestor: Node = null
	while owner_node != null and owner_node.get_parent() != null:
		if owner_node.get_parent() == slots:
			slot_ancestor = owner_node
			break
		owner_node = owner_node.get_parent()
	var idx: int = kids.find(slot_ancestor if slot_ancestor != null else _owner_ctrl)
	result["is_board"] = idx != -1
	result["index"] = idx
	var center_idx: int = int(sr.get("_last_winning_slot_idx")) if (sr as Object).has_method("get") else -1
	result["center"] = center_idx
	return result

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
