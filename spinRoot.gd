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

# SFX internals
var _sfx_pool: Array[AudioStreamPlayer] = []
var _crossings: PackedFloat32Array = []
var _next_cross := 0
var _prev_scroll: float = 0.0

@onready var spin_button: Button = %spinButton
@onready var coin_mgr: Node = get_node_or_null("/root/coinManager")
@onready var inventory_strip: Node = %inventoryStrip
@onready var artifact_strip: ArtifactStrip = %artifactContainerGrid
@onready var artifact_xp_bar: ArtifactXPBar = %artifactXPBar

func _ready() -> void:
	_rng.randomize()
	_wire_check()
	if artifact_xp_bar:
		artifact_xp_bar.set_segment_schedule(artifact_xp_schedule)
		if not artifact_xp_bar.artifact_selection_ready.is_connected(Callable(self, "_on_artifact_selection_ready")):
			artifact_xp_bar.artifact_selection_ready.connect(Callable(self, "_on_artifact_selection_ready"))

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

func handle_triggered_empty_removed(offset: int) -> void:
	if offset == 0:
		return
	if offset < 0:
		var current := offset
		while current < 0:
			var src_off := current - 1
			var dst_slot := _slot_for_offset(current)
			var src_slot := _slot_for_offset(src_off)
			if dst_slot == null:
				break
			var token = null
			if src_slot != null and src_slot.has_meta("token_data"):
				token = src_slot.get_meta("token_data")
			_apply_slot_token(dst_slot, token)
			if token == null:
				break
			current += 1
		if offset > -2:
			var boundary_slot := _slot_for_offset(-2)
			var src_slot := _slot_for_offset(-3)
			if boundary_slot != null and src_slot != null and src_slot.has_meta("token_data"):
				var tok = src_slot.get_meta("token_data")
				if tok != null:
					_apply_slot_token(boundary_slot, tok)
	else:
		var current := offset
		while current > 0:
			var src_off := current + 1
			var dst_slot := _slot_for_offset(current)
			var src_slot := _slot_for_offset(src_off)
			if dst_slot == null:
				break
			var token = null
			if src_slot != null and src_slot.has_meta("token_data"):
				token = src_slot.get_meta("token_data")
			_apply_slot_token(dst_slot, token)
			if token == null:
				break
			current -= 1
		if offset < 2:
			var boundary_slot := _slot_for_offset(2)
			var src_slot := _slot_for_offset(3)
			if boundary_slot != null and src_slot != null and src_slot.has_meta("token_data"):
				var tok = src_slot.get_meta("token_data")
				if tok != null:
					_apply_slot_token(boundary_slot, tok)
	_capture_slot_baseline_for_preview()

func _clone_token_ref(token):
	if token is Resource:
		var dup := (token as Resource).duplicate(true)
		if dup != null:
			_init_token_base_value(dup)
			return dup
	return token

func _capture_slot_baseline_for_preview() -> void:
	_slot_baseline_tokens.clear()
	var kids = slots_hbox.get_children()
	for node in kids:
		if node is Control:
			var ctrl: Control = node as Control
			if !ctrl.has_meta("token_data"):
				continue
			var tok = ctrl.get_meta("token_data")
			_slot_baseline_tokens[ctrl] = _clone_token_ref(tok)
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
	if not _inventory_preview_active:
		_set_inventory_preview(true)
	_preview_visible = true
	_apply_baseline_to_slots()
	if not was_active:
		emit_signal("eye_hover_started")

func hide_base_preview() -> void:
	if _base_preview_locked:
		return
	var was_active := _preview_visible
	_preview_visible = false
	_restore_slots_from_preview()
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
	_preview_slot_cache.clear()

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
	if _current_tween and _current_tween.is_running() and _current_tween.has_method("set_speed_scale"):
		_current_tween.set_speed_scale(factor)
		return true
	return false

func spin() -> void:
	if _spinning:
		return

	_inventory_before_spin = _deep_copy_inventory(items)
	hide_base_preview()

	_spin_done = false
	_spinning = true
	_apply_spin_button_state()

	# 1) PRE-CULL
	while _spin_history_counts.size() >= max_history_spins:
		_remove_oldest_spin()

	# 2) BUILD lap
	var laps = _rng.randi_range(min_laps, max_laps)
	var appended = _build_strip_for_spin(laps)
	_spin_history_counts.push_back(appended)

	# 3) flush
	await get_tree().process_frame

	# 4) pick winner (4th from end)
	var win_idx = slots_hbox.get_child_count() - 4
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

	_current_tween = get_tree().create_tween()
	_current_tween.tween_property(scroll_container, "scroll_horizontal", overshoot_scroll, spin_duration_sec).set_trans(trans).set_ease(easing)

	await _current_tween.finished

	if abs(_overshoot_offset) > 0.5:
		_current_tween = get_tree().create_tween()
		_current_tween.tween_property(scroll_container, "scroll_horizontal", _target_scroll, overshoot_settle_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await _current_tween.finished
	else:
		scroll_container.scroll_horizontal = _target_scroll

	_finish_spin()

func _build_strip_for_spin(laps: int) -> int:
	var count = 0
	for lap in range(laps):
		var lap_items = items.duplicate()
		lap_items.shuffle()
		for token in lap_items:
			_add_slot(token)
			count += 1
	return count

func _remove_oldest_spin() -> void:
	var remove_count = _spin_history_counts.pop_front()
	for i in range(remove_count):
		if slots_hbox.get_child_count() == 0:
			break
		var child = slots_hbox.get_child(0) as Control
		slots_hbox.remove_child(child)
		child.free()

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
	for i in range(max(1, copies)):
		var inst: TokenLootData = token if i == 0 else ((token as Resource).duplicate(true) as TokenLootData)
		_init_token_base_value(inst)
		var idx := _find_empty_index_in_items(empty_path)
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

func choose_target_offset(exclude_center: bool = true) -> int:
	# Allow player to click one of the currently triggered slots (neighbors + edges), optionally excluding center.
	var offsets: Array[int] = [-2, -1, 0, 1, 2]
	if exclude_center:
		offsets = [-2, -1, 1, 2]
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
	return int(picked)

func _on_target_pick_pressed(off: int) -> void:
	emit_signal("target_chosen", off)

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
