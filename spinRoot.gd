extends Control

signal spin_finished(selected: TokenLootData, total_value: int)
signal eye_hover_started
signal eye_hover_ended

# Inspector-driven references
@export var scroll_container: ScrollContainer
@export var slots_hbox: HBoxContainer
@export var slot_item_scene: PackedScene
@export var class_data: CharacterClassData
@export var artifact_xp_schedule: Array[int] = [5, 5, 5, 5, 5]
@export var peek_left_container: Control
@export var peek_right_container: Control

@onready var main_ui := get_tree().get_root().get_node("mainUI") as Control

# Popup scene is only forwarded to CoinManager; not used locally
@export var floating_label_scene: PackedScene

# Spin behavior
@export_range(1, 3) var min_laps := 3
@export_range(2, 4) var max_laps := 4
@export var spin_duration_sec := 5
@export var trans := Tween.TRANS_CUBIC
@export var easing := Tween.EASE_OUT
@export_range(0.0, 1.5, 0.01) var overshoot_slot_fraction := 0.65
@export_range(0.0, 0.5, 0.01) var undershoot_slot_fraction := 0.35
@export var overshoot_settle_duration := 0.25

# Selector alignment (0 = left, 0.5 = center, 1 = right)
@export_range(0.0, 1.0, 0.01) var selector_align_ratio := 0.5
@export var max_history_spins := 1

# Slot-pass SFX
@export var pass_sfx: AudioStream
@export var pass_sfx_bus: String = "SFX"
@export var pass_sfx_volume_db: float = 0.0
@export var pass_sfx_pitch_jitter: float = 0.05  # Â±5%

# Internal state
var items: Array[TokenLootData] = []
var _spin_done := false
var _current_tween
var _target_scroll := 0
var _win_item: TokenLootData
var _last_winning_slot_idx := -1
var _spinning := false
var _rng := RandomNumberGenerator.new()
var _spin_history_counts: Array[int] = []
var _last_spin_baseline: Array = []
var _preview_slot_cache: Dictionary = {}
var _preview_popups: Array[Node] = []
var _preview_visible := false
var _base_preview_locked := false
var _inventory_before_spin: Array = []
var _inventory_preview_active := false
var _slot_baseline_tokens: Dictionary = {}
var _overshoot_offset: float = 0.0
var _speedup_factor: float = 1.0
var _baseline_spin_distance: float = 0.0
var _spin_duration_scale: float = 1.0
var _recycle_queue: Array = []
const WINNER_RIGHT_BUFFER := 4
const PEEK_NAME_LEFT := "PeekLeftSlot"
const PEEK_NAME_RIGHT := "PeekRightSlot"
var _peek_left_slot: Control = null
var _peek_right_slot: Control = null
var _peek_refresh_pending := false
var _peek_update_suspensions := 0
var _peek_preview_snapshot: Dictionary = {}

# SFX internals
var _sfx_pool: Array[AudioStreamPlayer] = []
var _crossings: PackedFloat32Array = []
var _next_cross := 0
var _prev_scroll: float = 0.0

# Target selection arrows
 

@onready var spin_button: Button = %spinButton
@onready var coin_mgr: Node = get_node_or_null("/root/coinManager")
@onready var inventory_strip: Node = %inventoryStrip
@onready var artifact_strip: ArtifactStrip = %artifactContainerGrid
@onready var artifact_xp_bar: ArtifactXPBar = %artifactXPBar
@onready var ability_button: Control = %abilityButton

func _ready() -> void:
	_rng.randomize()
	_wire_check()
	if artifact_xp_bar:
		artifact_xp_bar.set_segment_schedule(artifact_xp_schedule)
		if not artifact_xp_bar.artifact_selection_ready.is_connected(Callable(self, "_on_artifact_selection_ready")):
			artifact_xp_bar.artifact_selection_ready.connect(Callable(self, "_on_artifact_selection_ready"))

	if ability_button:
		ability_button.mouse_filter = Control.MOUSE_FILTER_STOP
		if not ability_button.gui_input.is_connected(Callable(self, "_on_ability_button_gui_input")):
			ability_button.gui_input.connect(Callable(self, "_on_ability_button_gui_input"))

	if class_data:
		# Snapshot baseline values for authoring resources, then clone unique instances for the run
		_snapshot_base_values(class_data.startingTokens)
		items = _deep_copy_inventory(class_data.startingTokens)
		_snapshot_base_values(items)
	else:
		push_error("spinRoot: class_data NOT assigned")

	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_DISABLED
	slots_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_hbox.size_flags_vertical   = Control.SIZE_FILL
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical   = Control.SIZE_FILL
	# Constrain visible slots to the triggered window + immediate neighbors
	var slot_width := 0.0
	if slot_item_scene != null:
		var temp = slot_item_scene.instantiate()
		if temp is Control:
			slot_width = float((temp as Control).custom_minimum_size.x)
		if temp != null:
			temp.queue_free()
	if slot_width <= 0.0:
		slot_width = 256.0
	var separation := float(slots_hbox.get_theme_constant("separation"))
	var target_width := slot_width * 5.0 + separation * 4.0
	slots_hbox.custom_minimum_size.x = target_width
	if scroll_container != null:
		scroll_container.custom_minimum_size.x = target_width

	_init_peek_slots()
	_rebuild_idle_strip()
	_update_inventory_strip()
	_inventory_before_spin = _deep_copy_inventory(items)
	_capture_slot_baseline_for_preview()

	if artifact_strip:
		artifact_strip.clear_artifacts()

	spin_button.pressed.connect(_on_spin_button_pressed)
	_apply_spin_button_state()

	if coin_mgr:
		if coin_mgr.has_method("bind_totals_owner"):
			var owner_node: Node = main_ui if main_ui != null else self
			coin_mgr.call("bind_totals_owner", owner_node)
		if coin_mgr.has_signal("winner_description_shown"):
			coin_mgr.connect("winner_description_shown", Callable(self, "_on_winner_description_shown"))
		if coin_mgr.has_signal("spin_totals_ready"):
			coin_mgr.connect("spin_totals_ready", Callable(self, "_on_spin_totals_ready"))
			 # NEW: when a loot choice is made, append it to the future spin pool
		if coin_mgr.has_signal("loot_choice_selected"):
			coin_mgr.connect("loot_choice_selected", Callable(self, "_on_loot_choice_selected"))
		if coin_mgr.has_signal("loot_choice_replaced"):
			coin_mgr.connect("loot_choice_replaced", Callable(self, "_on_loot_choice_replaced"))
		if coin_mgr.has_signal("loot_choice_needed"):
			coin_mgr.connect("loot_choice_needed", Callable(self, "_on_loot_choice_needed"))
		if coin_mgr.has_signal("game_reset"):
			coin_mgr.connect("game_reset", Callable(self, "_on_game_reset"))
		if coin_mgr.has_signal("artifact_list_changed") and not coin_mgr.is_connected("artifact_list_changed", Callable(self, "_on_artifact_list_changed")):
			coin_mgr.connect("artifact_list_changed", Callable(self, "_on_artifact_list_changed"))
		if artifact_strip and coin_mgr.has_method("get_active_artifacts"):
			var art_list = coin_mgr.call("get_active_artifacts")
			artifact_strip.set_artifacts(art_list)
	else:
		push_warning("spinRoot: CoinManager autoload not found. Using fallback tally (no effects).")

	# Build a small audio pool
	if pass_sfx != null:
		for i in range(4):
			var p := AudioStreamPlayer.new()
			p.stream = pass_sfx
			p.bus = pass_sfx_bus
			p.volume_db = pass_sfx_volume_db
			add_child(p)
			_sfx_pool.append(p)

func _wire_check() -> void:
	if scroll_container == null:
		push_error("spinRoot: scroll_container NOT assigned")
	if slots_hbox == null:
		push_error("spinRoot: slots_hbox NOT assigned")
	if slot_item_scene == null:
		push_error("spinRoot: slot_item_scene NOT assigned")
	if class_data == null:
		push_error("spinRoot: class_data NOT assigned (.tres)")
	if floating_label_scene == null:
		push_warning("spinRoot: floating_label_scene NOT assigned (only needed if CoinManager uses it)")

func _rebuild_idle_strip() -> void:
	_clear(slots_hbox)
	for it in items:
		_add_slot(it)
	scroll_container.scroll_horizontal = 0
	_update_inventory_strip()
	_capture_slot_baseline_for_preview()

func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()

func _add_slot(it: TokenLootData) -> void:
	if slot_item_scene == null:
		push_error("spinRoot: slot_item_scene is null")
		return

	var slot = slot_item_scene.instantiate()
	if not slot is Control:
		push_error("spinRoot: slot_item_scene root is not Control")
		return

	var ctrl = slot as Control
	if ctrl.custom_minimum_size == Vector2.ZERO:
		ctrl.custom_minimum_size = Vector2(256, 256)
	ctrl.set_meta("spin_root_ref", self)

	# Apply visual data from your slot scene (if it supports it)
	if ctrl.has_method("_apply"):
		ctrl.call("_apply", it)
	else:
		for p in ctrl.get_property_list():
			if p.get("name", "") == "data":
				ctrl.set("data", it)
				break

	# Provide data for the tooltip/effects
	ctrl.set_meta("token_data", it)

	# Disable default string tooltip (avoid double-tooltips)
	ctrl.tooltip_text = ""

	# Ensure the spawner exists
	if ctrl.get_node_or_null("TooltipSpawner") == null:
		var tip := TooltipSpawner.new()
		tip.name = "TooltipSpawner"
		ctrl.add_child(tip)

	slots_hbox.add_child(ctrl)
	# Ensure inventory strip stays in sync if we ever add dynamically
	_update_inventory_strip()

# Spin button behavior:
# - When idle: starts a new spin
# - When spinning: speeds up only the reel tween (no CoinManager step acceleration)
func _on_spin_button_pressed() -> void:
	if _spinning:
		_try_speedup(5.0)
		return
	if coin_mgr and coin_mgr.has_method("can_begin_spin"):
		var can_spin = coin_mgr.call("can_begin_spin")
		if not bool(can_spin):
			return
	# Increment spin counter immediately on press
	if coin_mgr and coin_mgr.has_method("begin_spin"):
		coin_mgr.call("begin_spin")
	spin()

func _apply_spin_button_state() -> void:
	if not is_instance_valid(spin_button):
		return
	var lock_spin := false
	if coin_mgr and coin_mgr.has_method("can_begin_spin"):
		lock_spin = not bool(coin_mgr.call("can_begin_spin"))
	if _spinning:
		spin_button.text = "Speed up"
		spin_button.tooltip_text = "Click to speed up the reel"
		spin_button.disabled = false
	else:
		if lock_spin:
			spin_button.text = "Select Target"
			spin_button.tooltip_text = "Pick a target for the active ability"
			spin_button.disabled = true
		else:
			spin_button.text = "Spin"
			spin_button.tooltip_text = ""
			spin_button.disabled = false

func _set_spin_button_enabled(enabled: bool) -> void:
	if not is_instance_valid(spin_button):
		return
	spin_button.disabled = not enabled
	if enabled:
		spin_button.tooltip_text = ""
		_apply_spin_button_state()
	else:
		if spin_button.text == "":
			spin_button.text = "Spin"
			spin_button.tooltip_text = "Please wait..."


func _is_spin_button_enabled() -> bool:
	if not is_instance_valid(spin_button):
		return false
	return not spin_button.disabled

func _finish_spin() -> void:
	# Keep _spinning true until totals are applied (or fallback finishes)
	var neighbors: Array = _gather_neighbor_tokens(_last_winning_slot_idx)
	_capture_slot_baseline_for_preview()

	# Preferred path: CoinManager orchestrates visuals; pass slot_map and optional popup scene
	if coin_mgr and coin_mgr.has_method("play_spin"):
		var result: Dictionary = await coin_mgr.call("play_spin", _win_item, neighbors, {
			"class_data": class_data,
			"defer_winner_active": true,
			"slot_map": _build_slot_map(),
			"spin_root": self,
			"floating_label_scene": floating_label_scene
		})
		emit_signal("spin_finished", _win_item, int(result.get("spin_total", 0)))
		# _on_spin_totals_ready will flip _spinning to false and restore button state
		return

	# Fallback: no animations/popups; just sum values
	push_warning("spinRoot: CoinManager not found; fallback tally (no effects, no visuals).")
	_last_spin_baseline.clear()
	hide_base_preview()
	var sequence: Array[int] = [-2, -1, 0, 1, 2]
	var spin_total := 0
	for offset in sequence:
		var idx: int = _last_winning_slot_idx + offset
		if idx < 0 or idx >= slots_hbox.get_child_count():
			continue
		var slot := slots_hbox.get_child(idx) as Control
		var tdata := slot.get_meta("token_data") as TokenLootData
		spin_total += (tdata.value if offset != 0 else _win_item.value)

	emit_signal("spin_finished", _win_item, spin_total)
	_spinning = false
	_apply_spin_button_state()
	set_process(false)
	_crossings.clear()
	_next_cross = 0

func _build_slot_map() -> Dictionary:
	var m := {}
	for off in [-2, -1, 0, 1, 2]:
		var node := _slot_for_offset(int(off))
		if node != null:
			m[int(off)] = node
	return m

func _gather_neighbor_tokens(center_idx: int) -> Array:
	var kids = slots_hbox.get_children()
	var order: Array[int] = [-2, -1, 1, 2]
	var out: Array = []
	for offset in order:
		var idx: int = center_idx + int(offset)
		if idx >= 0 and idx < kids.size():
			var ctrl = kids[idx] as Control
			out.append(ctrl.get_meta("token_data"))
	return out

func _slot_for_offset(offset: int) -> Control:
	var idx: int = _last_winning_slot_idx + offset
	if idx < 0 or idx >= slots_hbox.get_child_count():
		return null
	return slots_hbox.get_child(idx) as Control

func _apply_slot_token(slot: Control, token) -> void:
	if slot == null:
		return
	if coin_mgr == null:
		coin_mgr = get_node_or_null("/root/coinManager")
	if token == null:
		var prev_token = null
		if slot.has_meta("token_data"):
			prev_token = slot.get_meta("token_data")
			slot.remove_meta("token_data")
		if coin_mgr != null and coin_mgr.has_method("_unregister_token_control") and prev_token != null:
			coin_mgr.call("_unregister_token_control", prev_token, slot)
		if slot.has_method("_apply"):
			slot.call("_apply", null)
		else:
			var si := slot.get_node_or_null("slotItem")
			if si != null and si.has_method("set"):
				si.set("data", null)
		notify_board_slot_changed(slot)
		return
	if coin_mgr != null and coin_mgr.has_method("_apply_token_to_slot"):
		coin_mgr.call("_apply_token_to_slot", slot, token)
	else:
		slot.set_meta("token_data", token)
		if slot.has_method("_apply"):
			slot.call("_apply", token)
		else:
			var si2 := slot.get_node_or_null("slotItem")
			if si2 != null and si2.has_method("set"):
				si2.set("data", token)
	notify_board_slot_changed(slot)

func handle_triggered_empty_removed(offset: int) -> void:
	if offset == 0:
		return
	var step := 1 if offset > 0 else -1
	var winner_idx := _last_winning_slot_idx
	var dst_idx := winner_idx + offset
	var children := slots_hbox.get_children()
	if dst_idx < 0 or dst_idx >= children.size():
		return
	while true:
		var dst_slot_node := children[dst_idx]
		if dst_slot_node == null or not (dst_slot_node is Control):
			break
		var dst_slot := dst_slot_node as Control
		var dst_prev_token = null
		if dst_slot.has_meta("token_data"):
			dst_prev_token = dst_slot.get_meta("token_data")
		var search_idx := dst_idx + step
		var found_slot: Control = null
		var found_token = null
		while search_idx >= 0 and search_idx < children.size():
			var src_node := children[search_idx]
			if src_node == null or not (src_node is Control):
				search_idx += step
				continue
			var src_slot := src_node as Control
			var tok = null
			if src_slot.has_meta("token_data"):
				tok = src_slot.get_meta("token_data")
			if tok == null:
				search_idx += step
				continue
			found_slot = src_slot
			found_token = tok
			break
		if found_token == null:
			_apply_slot_token(dst_slot, null)
			break
		_apply_slot_token(dst_slot, found_token)
		if found_slot != null and found_slot != dst_slot:
			if dst_prev_token != null:
				_apply_slot_token(found_slot, dst_prev_token)
			else:
				_apply_slot_token(found_slot, null)
			dst_idx = children.find(found_slot)
			if dst_idx == -1:
				break
		else:
			dst_idx += step
		if dst_idx < 0 or dst_idx >= children.size():
			break
	_debug_spin_window("After collapse offset=%d" % offset)
	_capture_slot_baseline_for_preview()

func _clone_token_ref(token):
	if token is Resource:
		var dup := (token as Resource).duplicate(true)
		if dup != null:
			_init_token_base_value(dup)
			return dup
	return token

func _init_peek_slots() -> void:
	_peek_left_slot = _prepare_peek_holder(peek_left_container, PEEK_NAME_LEFT)
	_peek_right_slot = _prepare_peek_holder(peek_right_container, PEEK_NAME_RIGHT)
	_update_peek_tokens()

func notify_board_slot_changed(slot: Control) -> void:
	if slot == null or not is_instance_valid(slot):
		return
	if slots_hbox == null or not is_instance_valid(slots_hbox):
		return
	if slot.get_parent() != slots_hbox:
		return
	_queue_peek_refresh()

func _queue_peek_refresh() -> void:
	_peek_refresh_pending = true
	if _peek_update_suspensions > 0:
		return
	_flush_peek_refresh()

func _flush_peek_refresh() -> void:
	if not _peek_refresh_pending:
		return
	if _peek_update_suspensions > 0:
		return
	_peek_refresh_pending = false
	_update_peek_tokens()

func _prepare_peek_holder(container: Control, slot_name: String) -> Control:
	if container == null:
		return null
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.anchor_left = 0.0
	container.anchor_top = 0.0
	container.anchor_right = 0.0
	container.anchor_bottom = 0.0
	container.offset_left = 0.0
	container.offset_top = 0.0
	container.offset_right = 0.0
	container.offset_bottom = 0.0
	container.modulate = Color(1.0, 1.0, 1.0, 0.85)
	container.visible = false
	var existing_tip := container.get_node_or_null("TooltipSpawner")
	for child in container.get_children():
		if child == existing_tip:
			continue
		child.queue_free()
	if slot_item_scene == null:
		return null
	var inst = slot_item_scene.instantiate()
	if inst == null or not (inst is Control):
		return null
	var ctrl := inst as Control
	ctrl.name = slot_name
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.focus_mode = Control.FOCUS_NONE
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
	container.add_child(ctrl)
	if existing_tip == null:
		existing_tip = TooltipSpawner.new()
		existing_tip.name = "TooltipSpawner"
		container.add_child(existing_tip)
	else:
		container.move_child(existing_tip, container.get_child_count() - 1)
	container.set_meta("tooltip_base_only", true)
	container.set_meta("tooltip_dim_all", true)
	if existing_tip != null:
		existing_tip.set_meta("tooltip_dim_all", true)
	return ctrl

func _update_peek_tokens() -> void:
	_peek_refresh_pending = false
	_update_single_peek(peek_left_container, _peek_left_slot, -1)
	_update_single_peek(peek_right_container, _peek_right_slot, 1)

func _snapshot_peek_state() -> void:
	_peek_preview_snapshot.clear()
	_peek_preview_snapshot["left"] = _capture_peek_wrapper_state(peek_left_container, _peek_left_slot)
	_peek_preview_snapshot["right"] = _capture_peek_wrapper_state(peek_right_container, _peek_right_slot)

func _capture_peek_wrapper_state(wrapper: Control, slot_display: Control) -> Dictionary:
	var snap: Dictionary = {}
	if wrapper == null or slot_display == null:
		return snap
	snap["visible"] = wrapper.visible
	var token = null
	if wrapper.has_meta("token_data"):
		token = wrapper.get_meta("token_data")
	if token != null:
		snap["token"] = _clone_token_ref(token)
	else:
		snap["token"] = null
	return snap

func _restore_peek_snapshot() -> void:
	_apply_peek_snapshot_to_wrapper(peek_left_container, _peek_left_slot, _peek_preview_snapshot.get("left", {}))
	_apply_peek_snapshot_to_wrapper(peek_right_container, _peek_right_slot, _peek_preview_snapshot.get("right", {}))
	_peek_preview_snapshot.clear()

func _apply_peek_snapshot_to_wrapper(wrapper: Control, slot_display: Control, snap) -> void:
	if wrapper == null or slot_display == null:
		return
	var token = null
	if snap is Dictionary:
		token = snap.get("token", null)
	if token != null:
		token = _clone_token_ref(token)
	_set_slot_token(slot_display, token)
	var tip := wrapper.get_node_or_null("TooltipSpawner")
	if token == null:
		wrapper.visible = false
		wrapper.set_meta("token_data", null)
		if tip != null:
			tip.set_meta("token_data", null)
		return
	wrapper.visible = bool((snap is Dictionary) and snap.get("visible", true))
	wrapper.set_meta("token_data", token)
	wrapper.set_meta("tooltip_base_only", true)
	wrapper.set_meta("tooltip_dim_all", true)
	if tip != null:
		tip.set_meta("token_data", token)
		tip.set_meta("tooltip_dim_all", true)

func _push_peek_suspend() -> void:
	_peek_update_suspensions += 1

func _pop_peek_suspend() -> void:
	if _peek_update_suspensions > 0:
		_peek_update_suspensions -= 1
	if _peek_update_suspensions == 0 and _peek_refresh_pending:
		_flush_peek_refresh()

func _find_peek_target(sign: int) -> Control:
	if sign == 0:
		return null
	var step := -1 if sign < 0 else 1
	var offset := -3 if sign < 0 else 3
	var guard := 0
	while guard < 16:
		var slot := _slot_for_offset(offset)
		if slot == null:
			return null
		if slot.has_meta("token_data") and slot.get_meta("token_data") != null:
			var tok = slot.get_meta("token_data")
			if tok == null or _is_empty_token_local(tok):
				offset += step
				guard += 1
				continue
			return slot
		offset += step
		guard += 1
	return null

func _update_single_peek(wrapper: Control, slot_display: Control, side_sign: int) -> void:
	if wrapper == null:
		return
	var tip := wrapper.get_node_or_null("TooltipSpawner")
	if slot_display == null:
		wrapper.visible = false
		wrapper.set_meta("token_data", null)
		if tip != null:
			tip.set_meta("token_data", null)
		return
	var target_slot := _find_peek_target(side_sign)
	if target_slot == null or not target_slot.has_meta("token_data"):
		_set_slot_token(slot_display, null)
		wrapper.visible = false
		wrapper.set_meta("token_data", null)
		if tip != null:
			tip.set_meta("token_data", null)
		return
	var token = target_slot.get_meta("token_data")
	if token == null:
		_set_slot_token(slot_display, null)
		wrapper.visible = false
		wrapper.set_meta("token_data", null)
		if tip != null:
			tip.set_meta("token_data", null)
		return
	var overlay := wrapper.get_parent()
	var base_ctrl: Control = null
	if side_sign < 0:
		base_ctrl = _slot_for_offset(-2)
	else:
		base_ctrl = _slot_for_offset(2)
	if base_ctrl == null and target_slot is Control:
		base_ctrl = target_slot as Control
	if overlay is Control and base_ctrl is Control:
		var base_pos := base_ctrl.global_position
		var base_size := base_ctrl.size
		var separation := float(slots_hbox.get_theme_constant("separation"))
		if side_sign < 0:
			base_pos.x -= base_size.x + separation
		else:
			base_pos.x += base_size.x + separation
		var local_pos = (overlay as Control).to_local(base_pos)
		wrapper.position = local_pos
		wrapper.size = base_size
	var clone = _clone_token_ref(token)
	_set_slot_token(slot_display, clone)
	wrapper.visible = true
	wrapper.set_meta("token_data", clone)
	wrapper.set_meta("tooltip_base_only", true)
	wrapper.set_meta("tooltip_dim_all", true)
	if tip != null:
		tip.set_meta("token_data", clone)
		tip.set_meta("tooltip_dim_all", true)

func _slot_offset_for_control(ctrl: Control) -> int:
	if ctrl == null or slots_hbox == null:
		return 1024
	var idx := slots_hbox.get_children().find(ctrl)
	if idx == -1:
		return 1024
	return idx - _last_winning_slot_idx

func _slot_is_empty(ctrl: Control) -> bool:
	if ctrl == null:
		return false
	if !ctrl.has_meta("token_data"):
		return true
	var tok = ctrl.get_meta("token_data")
	return tok == null or _is_empty_token_local(tok)

func _collect_board_empty_slots() -> Array:
	var empties: Array = []
	if slots_hbox == null:
		return empties
	for node in slots_hbox.get_children():
		if not (node is Control):
			continue
		var ctrl := node as Control
		if !_slot_is_empty(ctrl):
			continue
		var tok = ctrl.get_meta("token_data") if ctrl.has_meta("token_data") else null
		var idx := items.find(tok) if tok != null else -1
		if idx == -1:
			continue
		empties.append({
			"ctrl": ctrl,
			"offset": _slot_offset_for_control(ctrl),
			"inventory_index": idx,
			"token": tok
		})
	return empties

func place_token_random_board_empty(token, rng: RandomNumberGenerator = null, allow_append: bool = true) -> bool:
	if token == null or slots_hbox == null:
		return false
	var empties_data := _collect_board_empty_slots()
	if empties_data.is_empty():
		if not allow_append:
			return false
		_add_slot(token)
		if items.find(token) == -1:
			items.append(token)
			_update_inventory_strip()
			_refresh_inventory_baseline()
		_capture_slot_baseline_for_preview()
		return true
	var picker := rng
	if picker == null:
		picker = _rng
	if picker == null:
		picker = RandomNumberGenerator.new()
		picker.randomize()
	var pick_idx := picker.randi_range(0, empties_data.size() - 1)
	var entry := empties_data[pick_idx] as Dictionary
	var target_ctrl = entry.get("ctrl") if entry is Dictionary else null
	if target_ctrl == null:
		return false
	var inv_index := int(entry.get("inventory_index", -1)) if entry is Dictionary else -1
	_apply_slot_token(target_ctrl, token)
	if inv_index >= 0 and inv_index < items.size():
		items[inv_index] = token
		_update_inventory_strip()
		_refresh_inventory_baseline()
	_capture_slot_baseline_for_preview()
	return true

func _capture_slot_baseline_for_preview() -> void:
	_slot_baseline_tokens.clear()
	var offset_token_map: Dictionary = {}
	var kids = slots_hbox.get_children()
	for node in kids:
		if node is Control:
			var ctrl: Control = node as Control
			if !ctrl.has_meta("token_data"):
				continue
			var tok = ctrl.get_meta("token_data")
			_slot_baseline_tokens[ctrl] = _clone_token_ref(tok)
			var off := _slot_offset_for_control(ctrl)
			if off != 1024:
				offset_token_map[off] = tok
	_sync_triggered_baseline_from_offsets(offset_token_map)
	_update_peek_tokens()

func _sync_triggered_baseline_from_offsets(offset_token_map: Dictionary) -> void:
	if offset_token_map.is_empty():
		return
	if _last_winning_slot_idx < 0:
		return
	var baseline_by_offset: Dictionary = {}
	for entry in _last_spin_baseline:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var off_exists := int((entry as Dictionary).get("offset", 0))
		baseline_by_offset[off_exists] = entry
	var changed := false
	for off in [-2, -1, 0, 1, 2]:
		if not offset_token_map.has(off):
			continue
		var tok = offset_token_map[off]
		var has_entry := baseline_by_offset.has(off)
		var entry: Dictionary = {}
		if has_entry:
			entry = baseline_by_offset.get(off)
		if not has_entry:
			var kind_val := "passive"
			if off == 0:
				kind_val = "active"
			entry = {
				"offset": off,
				"kind": kind_val,
				"base_value": 0,
				"token": null
			}
			_last_spin_baseline.append(entry)
			baseline_by_offset[off] = entry
		var base_tok = tok
		entry["token"] = _clone_token_ref(base_tok)
		if base_tok != null and (base_tok as Object).has_method("get"):
			var nm = base_tok.get("name")
			if typeof(nm) == TYPE_STRING:
				entry["token_name"] = String(nm)
			elif entry.has("token_name"):
				entry.erase("token_name")
			var icon_val = base_tok.get("icon")
			if icon_val != null:
				entry["icon"] = icon_val
			elif entry.has("icon"):
				entry.erase("icon")
			var base_value_var = base_tok.get("value")
			if base_value_var != null:
				entry["base_value"] = int(base_value_var)
		else:
			entry["base_value"] = 0
			if entry.has("token_name"):
				entry.erase("token_name")
			if entry.has("icon"):
				entry.erase("icon")
		if base_tok is Resource:
			var rp := (base_tok as Resource).resource_path
			if rp != "":
				entry["resource_path"] = rp
			elif entry.has("resource_path"):
				entry.erase("resource_path")
		elif entry.has("resource_path"):
			entry.erase("resource_path")
		changed = true
	if changed and _preview_visible:
		_apply_baseline_to_slots()
func _compute_overshoot_scroll(target_scroll: float) -> float:
	_overshoot_offset = 0.0
	if overshoot_slot_fraction <= 0.0:
		return target_scroll
	var slot: Control = _slot_for_offset(0)
	var slot_width: float = 0.0
	if slot != null:
		slot_width = slot.size.x
	if slot_width <= 0.0:
		return target_scroll
	var max_over: float = slot_width * overshoot_slot_fraction
	var max_under: float = slot_width * undershoot_slot_fraction
	var offset: float = _rng.randf_range(-max_under, max_over)
	if abs(offset) < 1.0:
		return target_scroll
	var max_scroll: int = max(0, int(slots_hbox.size.x - scroll_container.size.x))
	var candidate: float = clamp(target_scroll + offset, 0.0, float(max_scroll))
	_overshoot_offset = candidate - target_scroll
	if abs(_overshoot_offset) < 1.0:
		_overshoot_offset = 0.0
		return target_scroll
	return candidate



# ---------- Eye hover preview ----------
func show_base_preview() -> void:
	if _spinning:
		return
	if _last_spin_baseline.is_empty():
		return
	var was_active := _preview_visible
	if not was_active:
		_snapshot_peek_state()
	if not _inventory_preview_active:
		_set_inventory_preview(true)
	_preview_visible = true
	_apply_baseline_to_slots()
	_update_peek_tokens()
	if not was_active:
		emit_signal("eye_hover_started")

func hide_base_preview() -> void:
	if _base_preview_locked:
		return
	var was_active := _preview_visible
	_preview_visible = false
	_restore_slots_from_preview()
	if was_active:
		_restore_peek_snapshot()
	_clear_preview_popups()
	if _inventory_preview_active:
		_set_inventory_preview(false)
	if was_active:
		emit_signal("eye_hover_ended")

func set_base_preview_lock(lock: bool) -> void:
	if lock == _base_preview_locked:
		return
	_base_preview_locked = lock
	if _base_preview_locked:
		show_base_preview()
	else:
		hide_base_preview()

func _apply_baseline_to_slots() -> void:
	_push_peek_suspend()
	_restore_slots_from_preview()
	_clear_preview_popups()
	var handled_slots: Dictionary = {}
	for entry in _ordered_baseline_entries():
		var offset := int(entry.get("offset", 0))
		var slot := _slot_for_offset(offset)
		if slot == null:
			continue
		handled_slots[slot] = true
		if !_preview_slot_cache.has(slot):
			var snapshot := {}
			snapshot["token"] = slot.get_meta("token_data")
			snapshot["popup_info"] = _capture_popup_state(slot)
			_preview_slot_cache[slot] = snapshot
		var preview_token = _build_preview_token(entry)
		_set_slot_token(slot, preview_token)
		var base_val := int(entry.get("base_value", entry.get("base", 0)))
		var popup_bundle := _ensure_popup_for_slot(slot)
		var label := popup_bundle.get("label") as Node
		if label != null:
			_set_preview_label_text(label, base_val)
		if bool(popup_bundle.get("created", false)):
			_preview_popups.append(popup_bundle.get("popup"))
	for key in _slot_baseline_tokens.keys():
		if !(key is Control):
			continue
		var ctrl: Control = key
		if ctrl == null or !is_instance_valid(ctrl):
			continue
		if handled_slots.has(ctrl):
			continue
		if !_preview_slot_cache.has(ctrl):
			var snapshot := {}
			snapshot["token"] = ctrl.get_meta("token_data")
			snapshot["popup_info"] = _capture_popup_state(ctrl)
			_preview_slot_cache[ctrl] = snapshot
		var base_token = _slot_baseline_tokens[ctrl]
		var apply_token = _clone_token_ref(base_token)
		_set_slot_token(ctrl, apply_token)
	_pop_peek_suspend()
	if _peek_refresh_pending:
		_flush_peek_refresh()

func _ordered_baseline_entries() -> Array:
	var ordered: Array = []
	var by_offset: Dictionary = {}
	for entry in _last_spin_baseline:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		by_offset[int((entry as Dictionary).get("offset", 0))] = entry
	for off in [-2, -1, 0, 1, 2]:
		if by_offset.has(off):
			ordered.append(by_offset[off])
			by_offset.erase(off)
	for remaining in by_offset.values():
		ordered.append(remaining)
	return ordered

func _build_preview_token(entry: Dictionary):
	var token = entry.get("token")
	var base_val := int(entry.get("base_value", entry.get("base", 0)))
	if token is Resource:
		var dup := (token as Resource).duplicate(true)
		if dup != null:
			var has_value_prop := false
			for prop in dup.get_property_list():
				if String(prop.get("name", "")) == "value":
					has_value_prop = true
					break
			if has_value_prop and (dup as Object).has_method("set"):
				dup.set("value", base_val)
			return dup
	return token

func _set_slot_token(slot: Control, token) -> void:
	if slot == null:
		return
	slot.set_meta("token_data", token)
	if slot.has_method("_apply"):
		slot.call("_apply", token)
		return
	for prop in slot.get_property_list():
		if String(prop.get("name", "")) == "data":
			slot.set("data", token)
			return
	var child := slot.get_node_or_null("slotItem")
	if child != null and child.has_method("set"):
		child.set("data", token)

func _set_inventory_preview(active: bool) -> void:
	_inventory_preview_active = active
	if inventory_strip == null or not is_instance_valid(inventory_strip):
		_update_inventory_strip()
	if inventory_strip == null or not inventory_strip.has_method("set_items"):
		return
	if active:
		inventory_strip.call("set_items", _deep_copy_inventory(_inventory_before_spin))
	else:
		inventory_strip.call("set_items", items)

func _deep_copy_inventory(source: Array[TokenLootData]) -> Array[TokenLootData]:
	var out: Array[TokenLootData] = []
	if source == null:
		return out
	for it in source:
		if it is Resource:
			var dup := (it as Resource).duplicate(true) as TokenLootData
			if dup != null:
				_init_token_base_value(dup)
				out.append(dup)
		else:
			out.append(it as TokenLootData)
	return out
	
func _refresh_inventory_baseline() -> void:
	if _spinning:
		return
	_inventory_before_spin = _deep_copy_inventory(items)
	if _inventory_preview_active:
		_set_inventory_preview(true)

func _resolve_preview_label(popup: Control) -> Node:
	if popup == null:
		return null
	var label := popup.get_node_or_null("labelMarginContainer/labelContainer/popupValueLabel")
	if label == null:
		label = popup.get_node_or_null("valueLabel")
	if label == null:
		for child in popup.get_children():
			if child is Label or child is RichTextLabel:
				label = child
				break
	return label

func _ensure_popup_for_slot(slot: Control) -> Dictionary:
	var popup := slot.get_node_or_null("FloatingPopup")
	var created := false
	if popup == null:
		popup = _create_preview_popup(slot)
		created = true
	return {
		"popup": popup,
		"label": _resolve_preview_label(popup),
		"created": created
	}

func _create_preview_popup(slot: Control) -> Control:
	var popup: Control = null
	if floating_label_scene != null:
		popup = floating_label_scene.instantiate() as Control
	if popup == null:
		popup = Control.new()
		popup.custom_minimum_size = Vector2(120, 48)
		var lbl := Label.new()
		lbl.name = "valueLabel"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		popup.add_child(lbl)
	popup.name = "FloatingPopup"
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if popup is CanvasItem:
		(popup as CanvasItem).z_index = 5
	slot.add_child(popup)
	var target_pos := Vector2(slot.size.x - popup.size.x, 15)
	popup.position = target_pos
	popup.call_deferred("set_position", target_pos)
	popup.call_deferred("set", "pivot_offset", popup.size * 0.5)
	popup.visible = true
	return popup

func _capture_popup_state(slot: Control) -> Dictionary:
	var info := {}
	var popup := slot.get_node_or_null("FloatingPopup")
	info["popup"] = popup
	var label := _resolve_preview_label(popup)
	if label is RichTextLabel:
		info["label_is_rich"] = true
		info["text"] = (label as RichTextLabel).text
		info["bbcode_enabled"] = (label as RichTextLabel).bbcode_enabled
	elif label is Label:
		info["label_is_rich"] = false
		info["text"] = (label as Label).text
	else:
		info["label_is_rich"] = false
		info["text"] = ""
	return info

func _set_preview_label_text(label: Node, value: int) -> void:
	var rich := "+%d[color=gold]G[/color]" % value
	var plain := "+%d G" % value
	if label is RichTextLabel:
		var rtl := label as RichTextLabel
		rtl.bbcode_enabled = true
		rtl.clear()
		rtl.parse_bbcode(rich)
	elif label is Label:
		(label as Label).text = plain

func _clear_preview_popups() -> void:
	for popup in _preview_popups:
		if popup != null and is_instance_valid(popup):
			popup.queue_free()
	_preview_popups.clear()

func _restore_slots_from_preview() -> void:
	var touched := not _preview_slot_cache.is_empty()
	_push_peek_suspend()
	for slot in _preview_slot_cache.keys():
		if slot == null or !is_instance_valid(slot):
			continue
		var snapshot = _preview_slot_cache[slot]
		if snapshot is Dictionary:
			_set_slot_token(slot, snapshot.get("token"))
			var popup_info = snapshot.get("popup_info")
			if popup_info is Dictionary:
				var popup = popup_info.get("popup")
				if popup != null and is_instance_valid(popup):
					var label := _resolve_preview_label(popup)
					if label != null:
						if bool(popup_info.get("label_is_rich", false)) and label is RichTextLabel:
							var rtl := label as RichTextLabel
							rtl.bbcode_enabled = bool(popup_info.get("bbcode_enabled", true))
							rtl.clear()
							rtl.parse_bbcode(String(popup_info.get("text", "")))
						elif not bool(popup_info.get("label_is_rich", false)) and label is Label:
							(label as Label).text = String(popup_info.get("text", ""))
	_pop_peek_suspend()
	_preview_slot_cache.clear()
	if not touched and _peek_update_suspensions == 0:
		_update_peek_tokens()

func _ingest_baseline_from_result(result: Dictionary) -> void:
	_last_spin_baseline.clear()
	if result == null:
		return
	var raw = result.get("baseline")
	if raw == null or not (raw is Array):
		return
	var by_offset: Dictionary = {}
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict := entry as Dictionary
		var offset := int(dict.get("offset", 0))
		var record := {}
		record["offset"] = offset
		record["token"] = dict.get("token")
		record["base_value"] = int(dict.get("base_value", dict.get("base", 0)))
		record["kind"] = String(dict.get("kind", ""))
		var name_str := String(dict.get("token_name", ""))
		if name_str.strip_edges() == "":
			var tk = record["token"]
			if tk != null and (tk as Object).has_method("get"):
				var nm = tk.get("name")
				if typeof(nm) == TYPE_STRING:
					name_str = String(nm)
		record["token_name"] = name_str
		var icon_val = dict.get("icon")
		if icon_val == null:
			var tk2 = record["token"]
			if tk2 != null and (tk2 as Object).has_method("get"):
				var icon_from_token = tk2.get("icon")
				if icon_from_token is Texture2D:
					icon_val = icon_from_token
		record["icon"] = icon_val
		var res_path = dict.get("resource_path")
		if res_path != null:
			record["resource_path"] = res_path
		by_offset[offset] = record
	for off in [-2, -1, 0, 1, 2]:
		if by_offset.has(off):
			_last_spin_baseline.append(by_offset[off])
			by_offset.erase(off)
	for remaining in by_offset.values():
		_last_spin_baseline.append(remaining)
	if _preview_visible:
		_apply_baseline_to_slots()

# ---------- Minimal reactions to CoinManager ----------

func _on_winner_description_shown(winner, text: String) -> void:
	pass

func _on_spin_totals_ready(result: Dictionary) -> void:
	_hide_target_cursor()
	
	_ingest_baseline_from_result(result)
	_spinning = false
	_apply_spin_button_state()
	set_process(false)
	_crossings.clear()
	_next_cross = 0

	# Optional per-spin breakdown (does not touch bank label)
	if main_ui:
		var totals_label := main_ui.get_node_or_null("SpinTotals") as RichTextLabel
		if totals_label:
			var c: Array = result.get("contributions", [])
			var text := ""
			for i in range(c.size()):
				var entry: Dictionary = c[i]
				var off: int = int(entry.get("offset", 0))
				var fin: int = int((entry.get("meta", {}) as Dictionary).get("final", 0))
				text += "[b]Offset %d[/b]: %d\n" % [off, fin]
			text += "\n[b]Spin Total:[/b] %d" % int(result.get("spin_total", 0))
			text += "\n[b]Bank:[/b] %d" % int(result.get("run_total", 0))
			totals_label.text = text

# ---------- Legacy helpers (not used when CoinManager is present) ----------

func _get_neighbor_info(center_idx: int) -> Array:
	var info := []
	var kids = slots_hbox.get_children()
	for offset in [-2, -1, 1, 2]:
		var idx: int = center_idx + int(offset)
		if idx >= 0 and idx < kids.size():
			var ctrl = kids[idx] as Control
			var td = ctrl.get_meta("token_data") as TokenLootData
			info.append({
				"name": td.name,
				"passive_gain": td.value
			})
	return info

func _try_speedup(factor: float) -> bool:
	var desired = max(1.0, factor)
	if is_equal_approx(_speedup_factor, desired):
		return false
	_speedup_factor = desired
	if _current_tween and _current_tween.is_running() and _current_tween.has_method("set_speed_scale"):
		_current_tween.set_speed_scale(_speedup_factor)
		return true
	return false

func spin() -> void:
	if _spinning:
		return

	_inventory_before_spin = _deep_copy_inventory(items)
	hide_base_preview()
	_hide_target_cursor()

	

	_spin_done = false
	_speedup_factor = 1.0
	_spin_duration_scale = 1.0
	_spinning = true
	_apply_spin_button_state()

	# 1) PRE-CULL
	while _spin_history_counts.size() >= max_history_spins:
		_remove_oldest_spin()

	# 2) BUILD lap
	var laps = _rng.randi_range(min_laps, max_laps)
	var appended = _build_strip_for_spin(laps)
	# Track both newly added slots and recycled buffer slots so next pre-cull
	# removes the exact count appended this spin.
	var appended_total = appended + _recycle_queue.size()
	_spin_history_counts.push_back(appended_total)
	_append_recycled_slots()

	# 3) flush
	await get_tree().process_frame

	# 4) pick winner (4th from end)
	var total_children := slots_hbox.get_child_count()
	var win_idx := total_children - 4
	if total_children >= WINNER_RIGHT_BUFFER + 5:
		win_idx = total_children - (WINNER_RIGHT_BUFFER + 3)
	win_idx = clampi(win_idx, 0, total_children - 1)
	_last_winning_slot_idx = win_idx
	var slot = slots_hbox.get_child(win_idx) as Control
	_win_item = slot.get_meta("token_data") as TokenLootData

	# 5) reset scroll
	scroll_container.scroll_horizontal = 0
	await get_tree().process_frame

	# 6) tween
	_target_scroll = _scroll_for_aligning(slot)
	var overshoot_scroll := _compute_overshoot_scroll(_target_scroll)

	# Prepare slot-pass thresholds and start polling
	var start_scroll := float(scroll_container.scroll_horizontal)
	_prepare_pass_sfx(start_scroll, overshoot_scroll)
	set_process(true)

	var travel_distance = abs(overshoot_scroll - start_scroll)
	if travel_distance < 1.0:
		travel_distance = 1.0
	if _baseline_spin_distance <= 0.0:
		_baseline_spin_distance = travel_distance
	_spin_duration_scale = travel_distance / _baseline_spin_distance
	_spin_duration_scale = clampf(_spin_duration_scale, 0.6, 1.6)
	var primary_duration = max(0.1, spin_duration_sec * _spin_duration_scale)

	_current_tween = get_tree().create_tween()
	if _speedup_factor != 1.0:
		_current_tween.set_speed_scale(_speedup_factor)
	_current_tween.tween_property(scroll_container, "scroll_horizontal", overshoot_scroll, primary_duration).set_trans(trans).set_ease(easing)

	await _current_tween.finished

	if abs(_overshoot_offset) > 0.5:
		var settle_duration = max(0.05, overshoot_settle_duration * clampf(_spin_duration_scale, 0.75, 1.25))
		_current_tween = get_tree().create_tween()
		if _speedup_factor != 1.0:
			_current_tween.set_speed_scale(_speedup_factor)
		_current_tween.tween_property(scroll_container, "scroll_horizontal", _target_scroll, settle_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await _current_tween.finished
	else:
		scroll_container.scroll_horizontal = _target_scroll

	_debug_spin_window("Spin settled")

	_finish_spin()

const VISIBLE_WINDOW_SPAN := 9 # offsets -4..4

func _build_strip_for_spin(laps: int) -> int:
	# Build each lap from a single shuffled order so repeated instances of the
	# same token are spaced exactly by inventory size (>= window span), avoiding
	# duplicates within the visible window at any time.
	var count = 0
	var base_order := items.duplicate()
	if base_order.size() > 1:
		base_order.shuffle()
	for lap in range(laps):
		for token in base_order:
			_add_slot(token)
			count += 1
	return count

func _remove_oldest_spin() -> void:
	var remove_count = _spin_history_counts.pop_front()
	var recycle_tokens: Array = []
	for i in range(remove_count):
		if slots_hbox.get_child_count() == 0:
			break
		var child = slots_hbox.get_child(0) as Control
		slots_hbox.remove_child(child)
		if recycle_tokens.size() < WINNER_RIGHT_BUFFER and child != null and child.has_meta("token_data"):
			var tok = child.get_meta("token_data")
			if tok != null:
				recycle_tokens.append(tok)
		if child != null:
			child.queue_free()
	if recycle_tokens.size() > 1:
		recycle_tokens.shuffle()
	_recycle_queue = recycle_tokens

func _append_recycled_slots() -> void:
	# Append only recycled tokens that will not cause the same token instance
	# to appear twice within the trailing visible window.
	if _recycle_queue.is_empty():
		return
	var tokens: Array = _recycle_queue.duplicate()
	_recycle_queue.clear()
	if tokens.size() > 1:
		tokens.shuffle()
	# Collect identities of tokens currently in the trailing window
	var recent: Array = []
	var kids := slots_hbox.get_children()
	var take = min(VISIBLE_WINDOW_SPAN, kids.size())
	for i in range(max(0, kids.size() - take), kids.size()):
		var n = kids[i]
		if n is Control and (n as Control).has_meta("token_data"):
			recent.append((n as Control).get_meta("token_data"))
	for tok in tokens:
		if tok == null:
			continue
		# Skip if same instance is already present in trailing window
		var exists := false
		for r in recent:
			if r == tok:
				exists = true
				break
		if exists:
			continue
		_add_slot(tok)
		recent.append(tok)

func _scroll_for_aligning(slot: Control) -> int:
	var slot_center = slot.position.x + slot.size.x * 0.5
	var marker_x = scroll_container.size.x * selector_align_ratio
	var raw = roundi(slot_center - marker_x)
	var max_scroll = max(0, int(slots_hbox.size.x - scroll_container.size.x))
	return clampi(raw, 0, max_scroll)

# ---------- Slot-pass SFX ----------

func _prepare_pass_sfx(from_scroll: float, to_scroll: float) -> void:
	_crossings.clear()
	_next_cross = 0
	_prev_scroll = from_scroll

	# Selector x inside the viewport
	var marker_x: float = scroll_container.size.x * selector_align_ratio

	# Compute all scroll values where the selector crosses each slot center
	var kids := slots_hbox.get_children()
	for n in kids:
		if n is Control:
			var c := n as Control
			var center_x: float = c.position.x + c.size.x * 0.5
			var s: float = center_x - marker_x
			if s > from_scroll and s <= to_scroll:
				_crossings.append(s)

	_crossings.sort()

func _process(_dt: float) -> void:
	if !_spinning or _crossings.is_empty():
		return

	var curr := float(scroll_container.scroll_horizontal)

	while _next_cross < _crossings.size() and curr >= _crossings[_next_cross]:
		_play_pass_tick()
		_next_cross += 1

	_prev_scroll = curr

func _play_pass_tick() -> void:
	if _sfx_pool.is_empty():
		return
	var player: AudioStreamPlayer = null
	for p in _sfx_pool:
		if !p.playing:
			player = p
			break
	if player == null:
		player = _sfx_pool[0]
	player.pitch_scale = 1.0 + _rng.randf_range(-pass_sfx_pitch_jitter, pass_sfx_pitch_jitter)
	player.play()

func _on_loot_choice_selected(round_num: int, token: TokenLootData) -> void:
	if token == null:
		return
	var copies := _copies_to_add_for_token(token)
	var added := _insert_token_replacing_empties(token, copies)
	_apply_on_added_abilities(added)
	_update_inventory_strip()
	_refresh_inventory_baseline()
	_apply_spin_button_state()

func _on_loot_choice_replaced(round_num: int, token: TokenLootData, index: int) -> void:
	# When CoinManager performs replacement directly into an inventory array,
	# just refresh our UI from current items.
	_update_inventory_strip()
	_refresh_inventory_baseline()
	_apply_spin_button_state()


func _on_artifact_selection_ready() -> void:
	if coin_mgr == null:
		coin_mgr = get_node_or_null("/root/coinManager")
	if coin_mgr != null and coin_mgr.has_method("queue_artifact_selection"):
		coin_mgr.call_deferred("queue_artifact_selection")

func _on_artifact_list_changed(artifacts: Array) -> void:
	if artifact_strip:
		artifact_strip.set_artifacts(artifacts)

func _on_loot_choice_needed(_round_num: int) -> void:
	_apply_spin_button_state()

func _copies_to_add_for_token(token: TokenLootData) -> int:
	var copies := 1
	if token != null and token.has_method("get"):
		var abilities = token.get("abilities")
		if abilities is Array:
			for ab in abilities:
				if ab == null:
					continue
				var tc = null
				if (ab as Object).has_method("get"):
					tc = ab.get("total_copies")
				if tc != null:
					copies = max(copies, int(tc))
	return max(1, copies)

func _insert_token_replacing_empties(token: TokenLootData, copies: int) -> Array[TokenLootData]:
	var empty_path: String = ""
	if coin_mgr != null and coin_mgr.has_method("get"):
		var ep = coin_mgr.get("empty_token_path")
		if typeof(ep) == TYPE_STRING:
			empty_path = String(ep)
	var added_count := 0
	var instances: Array[TokenLootData] = []
	var add_as_new_empty := _token_matches_empty(token, empty_path)
	for i in range(max(1, copies)):
		var inst: TokenLootData = token if i == 0 else ((token as Resource).duplicate(true) as TokenLootData)
		_init_token_base_value(inst)
		if add_as_new_empty:
			items.append(inst)
		else:
			var idx: int = _find_empty_index_in_items(empty_path)
			if idx >= 0:
				items[idx] = inst
			else:
				items.append(inst)
		added_count += 1
		instances.append(inst)
	if added_count > 0:
		_on_tokens_added_to_inventory(added_count)
	return instances

func _apply_on_added_abilities(instances: Array) -> void:
	if instances == null or instances.is_empty():
		return
	var ctx := {
		"spin_root": self,
		"coin_mgr": coin_mgr,
		"rng": _rng,
		"board_tokens": items
	}
	for inst in instances:
		if inst == null or not (inst as Object).has_method("get"):
			continue
		var abilities = inst.get("abilities")
		if abilities is Array:
			for ab in abilities:
				if ab == null: continue
				if (ab as Object).has_method("on_added_to_inventory"):
					(ab as Object).call_deferred("on_added_to_inventory", items, ctx, inst)

func add_empty_slots(count: int) -> void:
	if count <= 0:
		return
	var empty_path: String = "res://tokens/empty.tres"
	if coin_mgr != null and coin_mgr.has_method("get"):
		var ep = coin_mgr.get("empty_token_path")
		if typeof(ep) == TYPE_STRING:
			empty_path = String(ep)
	var empty_res = ResourceLoader.load(empty_path)
	if empty_res == null:
		return
	for i in range(count):
		var inst: Resource = (empty_res as Resource).duplicate(true)
		_init_token_base_value(inst)
		items.append(inst)
	_on_tokens_added_to_inventory(count)
	_update_inventory_strip()
	_refresh_inventory_baseline()

signal target_chosen(offset: int)

# ---- Target cursor overlay ----
var _target_cursor: Control = null
func _show_target_cursor(count: int) -> void:
	var ui := get_tree().get_root().get_node_or_null("mainUI") as Control
	if ui == null:
		return
	if _target_cursor != null and is_instance_valid(_target_cursor):
		if _target_cursor.has_method("set_count"):
			_target_cursor.call("set_count", count)
		return
	var scn := load("res://ui/TargetCursor.tscn")
	if scn is PackedScene:
		_target_cursor = (scn as PackedScene).instantiate() as Control
		if _target_cursor != null:
			if _target_cursor.has_method("set_count"):
				_target_cursor.call("set_count", count)
			ui.add_child(_target_cursor)

func _hide_target_cursor() -> void:
	if _target_cursor != null and is_instance_valid(_target_cursor):
		if _target_cursor.has_method("restore_cursor"):
			_target_cursor.call("restore_cursor")
		_target_cursor.queue_free()
	_target_cursor = null

func choose_target_offset(exclude_center: bool = true, ordinal: int = 1) -> int:
	# Allow player to click one of the currently triggered slots (neighbors + edges), optionally excluding center.
	var offsets: Array[int] = [-2, -1, 0, 1, 2]
	if exclude_center:
		offsets = [-2, -1, 1, 2]
	# Show overlay target cursor while awaiting selection
	_show_target_cursor(max(1, ordinal))
	var overlays: Array[Node] = []
	for off in offsets:
		var slot := _slot_for_offset(off)
		if slot == null:
			continue
		var btn := Button.new()
		btn.name = "_TargetPick"
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.modulate = Color(1, 1, 1, 0.001)
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		var slot_token = slot.get_meta("token_data") if slot.has_meta("token_data") else null
		if slot_token != null:
			btn.set_meta("token_data", slot_token)
			if btn.get_node_or_null("TooltipSpawner") == null:
				var pick_tip := TooltipSpawner.new()
				pick_tip.name = "TooltipSpawner"
				pick_tip.set_meta("token_data", slot_token)
				btn.add_child(pick_tip)
		if btn.is_connected("pressed", Callable(self, "_on_target_pick_pressed")):
			btn.pressed.disconnect(Callable(self, "_on_target_pick_pressed"))
		btn.pressed.connect(_on_target_pick_pressed.bind(off))
		slot.add_child(btn)
		overlays.append(btn)
	var picked: Variant = await self.target_chosen
	for ov in overlays:
		if ov != null and is_instance_valid(ov):
			ov.queue_free()
	_hide_target_cursor()
	return int(picked)

func _on_target_pick_pressed(off: int) -> void:
	_hide_target_cursor()
	emit_signal("target_chosen", off)

func _should_debug_spin() -> bool:
	if coin_mgr == null:
		coin_mgr = get_node_or_null("/root/coinManager")
	if coin_mgr == null:
		return false
	var dbg_val := false
	var dbg_prop = coin_mgr.get("debug_spin") if coin_mgr != null else null
	if typeof(dbg_prop) == TYPE_BOOL:
		dbg_val = dbg_prop
	return dbg_val

func _debug_token_name(token) -> String:
	if token == null:
		return "null"
	if (token as Object).has_method("get"):
		var nm = token.get("name")
		if typeof(nm) == TYPE_STRING:
			var s := String(nm).strip_edges()
			if s != "":
				return s
	if token is Resource:
		var path := (token as Resource).resource_path
		if path != "":
			var file := String(path.get_file())
			if file.ends_with(".tres"):
				file = file.trim_suffix(".tres")
			return file
	return str(token)

func _debug_spin_window(label: String) -> void:
	if not _should_debug_spin():
		return
	var entries: Array[String] = []
	for off in range(-4, 5):
		var slot := _slot_for_offset(off)
		var name := "null"
		if slot != null and slot.has_meta("token_data"):
			name = _debug_token_name(slot.get_meta("token_data"))
		entries.append("%d:%s" % [off, name])
	print("[SpinDebug] %s -> %s" % [label, ", ".join(entries)])
	# Optional: detect duplicates in the window by instance
	var seen: Array = []
	var dupes: Array[String] = []
	for off in range(-4, 5):
		var slot2 := _slot_for_offset(off)
		if slot2 == null or !slot2.has_meta("token_data"):
			continue
		var tk = slot2.get_meta("token_data")
		var found := false
		for s in seen:
			if s == tk: found = true; break
		if found:
			dupes.append(_debug_token_name(tk))
		else:
			seen.append(tk)
	if !dupes.is_empty():
		print("[SpinDebug] Duplicate instances in window: ", ", ".join(dupes))

func _is_empty_token_local(token) -> bool:
	if token == null:
		return true
	if coin_mgr != null:
		var empty_path = ""
		if coin_mgr.has_method("get"):
			var maybe = coin_mgr.get("empty_token_path")
			if typeof(maybe) == TYPE_STRING:
				empty_path = String(maybe)
		if empty_path != "" and token is Resource:
			var rp := (token as Resource).resource_path
			if rp != "" and rp == empty_path:
				return true
	if token is Object and (token as Object).has_method("get"):
		var nm = token.get("name")
		if typeof(nm) == TYPE_STRING:
			var s := String(nm).strip_edges().to_lower()
			if s == "empty" or s == "empty token":
				return true
		var is_empty = token.get("isEmpty")
		if is_empty != null and bool(is_empty):
			return true
	return false

func replace_token_in_inventory(old_token: Resource, new_token: Resource) -> void:
	if old_token == null or new_token == null:
		return
	var idx := -1
	for i in range(items.size()):
		if items[i] == old_token:
			idx = i
			break
	if idx == -1:
		# Try by name equality fallback
		var n_old := String(old_token.get("name")) if old_token.has_method("get") else ""
		for i in range(items.size()):
			var it = items[i]
			if it != null and (it as Object).has_method("get"):
				if String(it.get("name")) == n_old:
					idx = i
					break
	if idx == -1:
		return
	var inst: Resource = (new_token as Resource).duplicate(true)
	_init_token_base_value(inst)
	items[idx] = inst
	_update_inventory_strip()
	_refresh_inventory_baseline()

func _on_tokens_added_to_inventory(count: int) -> void:
	if count <= 0:
		return
	if artifact_xp_bar:
		artifact_xp_bar.add_tokens(count)

func _on_ability_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		if coin_mgr == null:
			coin_mgr = get_node_or_null("/root/coinManager")
		if coin_mgr != null and coin_mgr.has_method("queue_artifact_selection"):
			coin_mgr.call_deferred("queue_artifact_selection")

func _find_empty_index_in_items(empty_path: String) -> int:
	var candidates: Array[int] = []
	for i in range(items.size()):
		var t = items[i]
		if t == null:
			candidates.append(i)
			continue
		if empty_path.strip_edges() != "" and t is Resource:
			var rp := (t as Resource).resource_path
			if rp != "" and rp == empty_path:
				return i
		if t.has_method("get"):
			var is_empty = t.get("isEmpty")
			if is_empty != null and bool(is_empty):
				return i
			var nm = t.get("name")
			if typeof(nm) == TYPE_STRING:
				var s := String(nm).strip_edges().to_lower()
				if s == "empty" or s == "empty token":
					return i
	if candidates.size() > 0:
		return int(candidates[0])
	return -1

func _token_matches_empty(token, empty_path: String) -> bool:
	var normalized := String(empty_path).strip_edges()
	if token == null:
		return true
	if normalized != "" and token is Resource:
		var rp := (token as Resource).resource_path
		if rp != "" and rp == normalized:
			return true
	if token is Object and (token as Object).has_method("get"):
		var is_empty = token.get("isEmpty")
		if is_empty != null and bool(is_empty):
			return true
		var nm = token.get("name")
		if typeof(nm) == TYPE_STRING:
			var s := String(nm).strip_edges().to_lower()
			if s == "empty" or s == "empty token":
				return true
	return false

func _on_game_reset() -> void:
	# Reset items to starting tokens on game reset
	if class_data:
		# Restore baseline values on authoring resources, then rebuild items from that list
		_reset_array_to_base(class_data.startingTokens)
		items = _deep_copy_inventory(class_data.startingTokens)
		_rebuild_idle_strip()
	else:
		_update_inventory_strip()
	_inventory_before_spin = _deep_copy_inventory(items)
	if artifact_xp_bar:
		artifact_xp_bar.reset_bar()

func _update_inventory_strip() -> void:
	if inventory_strip == null:
		# Try resolving by unique name (owner mainUI)
		var ui := get_tree().get_root().get_node_or_null("mainUI")
		if ui:
			# First try unique-name resolution via the owner
			var uniq := ui.get_child(0) # noop to ensure tree is ready
			inventory_strip = ui.find_child("inventoryStrip", true, false)
	if inventory_strip and inventory_strip.has_method("set_items"):
		inventory_strip.call("set_items", items)

# ---- Baseline value helpers ----
func _init_token_base_value(tok: TokenLootData) -> void:
	if tok == null:
		return
	# Prefer CoinManager's initializer so any per-run offsets apply to this instance.
	if coin_mgr != null and coin_mgr.has_method("_init_token_base_value"):
		coin_mgr.call("_init_token_base_value", tok)
		return
	# Fallback: just stamp baseline meta
	if (tok as Object).has_method("has_meta") and tok.has_meta("base_value"):
		return
	var v = null
	if (tok as Object).has_method("get"):
		v = tok.get("value")
	if v != null and (tok as Object).has_method("set_meta"):
		tok.set_meta("base_value", int(v))

func _snapshot_base_values(arr: Array) -> void:
	if arr == null:
		return
	for t in arr:
		_init_token_base_value(t)

func _reset_array_to_base(arr: Array) -> void:
	if arr == null:
		return
	for t in arr:
		if t == null:
			continue
		if (t as Object).has_method("has_meta") and t.has_meta("base_value") and (t as Object).has_method("set"):
			var bv = t.get_meta("base_value")
			if bv != null:
				t.set("value", max(1, int(bv)))
