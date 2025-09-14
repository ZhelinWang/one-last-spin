extends Control

signal spin_finished(selected: TokenLootData, total_value: int)

# Inspector-driven references
@export var scroll_container: ScrollContainer
@export var slots_hbox: HBoxContainer
@export var slot_item_scene: PackedScene
@export var class_data: CharacterClassData

@onready var main_ui := get_tree().get_root().get_node("mainUI") as Control

# Popup scene is only forwarded to CoinManager; not used locally
@export var floating_label_scene: PackedScene

# Spin behavior
@export_range(1, 2, 1) var min_laps := 2
@export_range(2, 3, 1) var max_laps := 3
@export var spin_duration_sec := 6
@export var trans := Tween.TRANS_CUBIC
@export var easing := Tween.EASE_OUT

# Selector alignment (0 = left, 0.5 = center, 1 = right)
@export_range(0.0, 1.0, 0.01) var selector_align_ratio := 0.5
@export var max_history_spins := 1

# Slot-pass SFX
@export var pass_sfx: AudioStream
@export var pass_sfx_bus: String = "SFX"
@export var pass_sfx_volume_db: float = 0.0
@export var pass_sfx_pitch_jitter: float = 0.05  # ±5%

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

# SFX internals
var _sfx_pool: Array[AudioStreamPlayer] = []
var _crossings: PackedFloat32Array = []
var _next_cross := 0
var _prev_scroll: float = 0.0

@onready var spin_button: Button = %spinButton
@onready var coin_mgr: Node = get_node_or_null("/root/coinManager")
@onready var inventory_strip: Node = %inventoryStrip

func _ready() -> void:
	_rng.randomize()
	_wire_check()

	if class_data:
		items = class_data.startingTokens.duplicate()
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

	# Use a press handler that supports "Speed up" while spinning
	spin_button.pressed.connect(_on_spin_button_pressed)
	_apply_spin_button_state()

	# Bind totals owner so CoinManager can update %valueLabel and connect only minimal signals
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
		if coin_mgr.has_signal("game_reset"):
			coin_mgr.connect("game_reset", Callable(self, "_on_game_reset"))
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
	# Increment spin counter immediately on press
	if coin_mgr and coin_mgr.has_method("begin_spin"):
		coin_mgr.call("begin_spin")
	spin()

func _apply_spin_button_state() -> void:
	if not is_instance_valid(spin_button):
		return
	if _spinning:
		spin_button.text = "Speed up"
		spin_button.tooltip_text = "Click to speed up the reel"
	else:
		spin_button.text = "Spin"
		spin_button.tooltip_text = ""

func _finish_spin() -> void:
	# Keep _spinning true until totals are applied (or fallback finishes)
	var neighbors: Array = _gather_neighbor_tokens(_last_winning_slot_idx)

	# Preferred path: CoinManager orchestrates visuals; pass slot_map and optional popup scene
	if coin_mgr and coin_mgr.has_method("play_spin"):
		var result: Dictionary = await coin_mgr.call("play_spin", _win_item, neighbors, {
			"class_data": class_data,
			"defer_winner_active": true,
			"slot_map": _build_slot_map(),
			"floating_label_scene": floating_label_scene
		})
		emit_signal("spin_finished", _win_item, int(result.get("spin_total", 0)))
		# _on_spin_totals_ready will flip _spinning to false and restore button state
		return

	# Fallback: no animations/popups; just sum values
	push_warning("spinRoot: CoinManager not found; fallback tally (no effects, no visuals).")
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

# ---------- Minimal reactions to CoinManager ----------

func _on_winner_description_shown(winner, text: String) -> void:
	pass

func _on_spin_totals_ready(result: Dictionary) -> void:
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

	# Prepare slot-pass thresholds and start polling
	_prepare_pass_sfx(0.0, float(_target_scroll))
	set_process(true)

	_current_tween = get_tree().create_tween()
	_current_tween.tween_property(scroll_container, "scroll_horizontal", _target_scroll, spin_duration_sec).set_trans(trans).set_ease(easing)

	await _current_tween.finished
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
	items.append(token) # CoinManager already duplicates; each instance is unique
	_update_inventory_strip()

func _on_game_reset() -> void:
	# Reset items to starting tokens on game reset
	if class_data:
		items = class_data.startingTokens.duplicate()
		_rebuild_idle_strip()
	else:
		_update_inventory_strip()

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
