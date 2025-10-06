extends Node
class_name CoinManager

signal spin_sequence_started(ctx)
signal winner_description_shown(winner, text)
signal token_sequence_started(index: int, offset: int, contrib: Dictionary)
signal token_value_shown(index: int, offset: int, value: int, contrib: Dictionary)
signal token_step_applied(index: int, offset: int, step: Dictionary, new_value: int, contrib: Dictionary)
signal token_sequence_finished(index: int, offset: int, final_value: int, contrib: Dictionary)
signal spin_totals_ready(result: Dictionary)
signal round_ended(round_number: int, requirement: int, paid: bool)
signal game_over_shown(round_number: int, requirement: int, total_coins: int)
signal game_reset()

@export var empty_non_common_bonus_per: float = 0.02  

# Loot signals
signal loot_choice_needed(round_number: int)
signal loot_choice_selected(round_number: int, token)
signal loot_choice_replaced(round_number: int, token, index: int) # replaces first/last/random empty in inventory

signal artifact_selection_started(options: Array)
signal artifact_acquired(artifact: ArtifactData)
signal artifact_list_changed(artifacts: Array)

@export var step_delay_sec: float = 0.5
@export var passive_trigger_delay_sec: float = 0.5
@export var base_show_delay_sec: float = 0.2
@export var between_tokens_delay_sec: float = 0.2
@export var show_winner_desc_delay_sec: float = 1.0
@export var active_desc_pause_sec: float = 0.35
# (reverted) no global time scaling
@export_range(0.0, 5.0, 0.05) var loot_post_spin_delay: float = 1.5

# Game over / ante system (customizable)
@export var enable_game_over := true
@export var spins_per_round: int = 3
@export var ante_schedule: PackedInt32Array = [
	20,   # R1
	25,   # R2
	35,   # R3
	50,   # R4
	75,   # R5  (boss spike)
	85,   # R6
	100,  # R7
	150,  # R8
	175,  # R9
	300,  # R10 (boss spike)
	350,  # R11
	420,  # R12
	550,  # R13
	750,  # R14
	1000, # R15 (boss spike)
	1250, # R16
	1700, # R17
	2200, # R18
	3000, # R19
	4000  # R20 (boss spike)
]
@export var ante_increment_after_schedule: int = 20
@export var deduct_on_pay := true

# Overlay customization
@export var overlay_bg: Color = Color(0, 0, 0, 0.90)
@export var game_over_text: String = "GAME OVER"
@export var game_over_color: Color = Color8(246, 44, 37)
@export var last_spin_button_text: String = "ONE LAST SPIN?"

# Popup scene (used to render counting UI on slots via ctx.slot_map)
@export var floating_label_scene: PackedScene

# Loot rarity management class
@export var loot_rarity_schedule: LootRaritySchedule

# Bank label animation
@export var animate_bank: bool = true
@export var bank_anim_duration_sec: float = 1.5

# Loot config
@export var loot_options_count: int = 3
@export var loot_scan_root: String = "res://tokens"
@export var empty_token_path: String = "res://tokens/empty.tres"
@export var loot_title: String = "ROUND COMPLETE\n\n\nPICK A TOKEN"
@export var skip_button_text: String = "SKIP AND ADD AN EMPTY TOKEN"
# Assign your slotItem scene here (extends Button, property `data: TokenLootData`)
@export var token_icon_scene: PackedScene

@export_range(1, 5, 1) var artifact_options_count: int = 3
@export_range(1, 5, 1) var max_artifacts: int = 5
@export var artifact_loot_title: String = "ARTIFACT UNLOCKED\n\n\nCHOOSE AN ARTIFACT"
@export var artifact_scan_paths: PackedStringArray = PackedStringArray(["res://artifacts/data"])
@export var artifact_manual_pool: Array = []

@export var loot_tile_scale: float = 3.0

# Inventory wiring for replacement
@export var inventory_owner_path: NodePath
@export var inventory_property: String = "items"
@export_enum("first", "last", "random") var empty_replace_strategy: String = "first"

# Debugging
@export var debug_spin: bool = true

@export var screen_shake_light_threshold := 5
@export var screen_shake_moderate_threshold := 10
@export var screen_shake_heavy_threshold := 20
@export var screen_shake_light_intensity := 1.25
@export var screen_shake_moderate_intensity := 1.5
@export var screen_shake_heavy_intensity := 2
@export var screen_shake_duration := 0.5
@export var highlight_flash_color: Color = Color(0.588, 0.588, 0.588, 1.0)
@export var highlight_flash_in_sec: float = 0.8
@export var highlight_flash_out_sec: float = 0.8
@export var highlight_flash_pause_sec: float = 1.5
@export var temporary_gain_color: Color = Color8(80, 220, 80)
@export var temporary_loss_color: Color = Color8(220, 80, 80)

var total_active: int = 0
var total_passive: int = 0
var total_coins: int = 0
var spin_index: int = 0

var _artifacts: Array[ArtifactData] = []
var _artifact_library: Array[ArtifactData] = []
var _artifact_selection_active: bool = false
var _artifact_selection_queued: bool = false
var _artifact_current_options: Array[ArtifactData] = []
var _pending_loot_request: Dictionary = {}
var _loot_title_label: Label
var _totals_owner: Node = null # %valueLabel, %roundLabel, %deadlineLabel

const ROUND_PAY_BASE_RATE: float = 5.0
const ROUND_PAY_MAX_RATE: float = 500.0
const ROUND_PAY_ACCEL_PER_SEC: float = 1.35
const ROUND_PAY_MIN_FRAME: float = 1.0 / 240.0
const VALUE_LABEL_FONT_SIZE := 20
const VALUE_LABEL_OUTLINE_SIZE := 24

# Game Over overlay
var _round_pay_layer: CanvasLayer
var _round_pay_block: Control
var _round_pay_round_label: Label
var _round_pay_status_label: Label
var _round_pay_player_value_label: RichTextLabel
var _round_pay_required_value_label: RichTextLabel
var _go_layer: CanvasLayer
var _go_block: Control
var _go_btn: Button

# Loot overlay
var _loot_layer: CanvasLayer
var _loot_block: Control
var _loot_options_hbox: HBoxContainer
var _loot_skip_btn: Button
var _loot_rng := RandomNumberGenerator.new()
var _loot_last_round: int = 0
var _loot_selection_forced: bool = false
var _loot_selection_pending: bool = false
var _target_selection_pending: bool = false
# Removed FX overlay vars (reverted fly-to-total animation)

# Run state guards
var _game_over_active: bool = false
var _loot_gen: int = 0  # increments to invalidate any pending loot shows

# Cached refs
var _value_label: Node = null
var _bank_tween: Tween = null
var _shown_total: int = 0
var _active_effect_label: Node = null
var _token_value_offsets: Dictionary = {} # key (resource_path or name) -> cumulative permanent offset for this run
var _token_tag_offsets: Dictionary = {} # normalized tag -> cumulative permanent offset for this run
var _token_name_offsets: Dictionary = {} # normalized name -> cumulative permanent offset for this run
var _token_global_offset: int = 0 # global permanent offset applied to all tokens
var _effect_targets: Dictionary = {} # token_uid -> {targets: Array[int]}
var _token_controls: Dictionary = {} # token_uid -> Array[WeakRef]
var _current_effect_source: Object = null
var _active_effect_highlight: Dictionary = {}
var _highlight_tweens: Array = []
var _next_highlight_uid: int = 1
var _value_label_defer_depth: int = 0
const META_ZERO_REPLACED := "__zero_replaced"
const META_ZERO_REASON := "__zero_reason"
const ZERO_REPLACEMENT_VALUE := 1
const TEMP_META_DELTA := "__temp_spin_delta"
const TEMP_META_COLOR := "__temp_spin_color"
const POPUP_META_TOTAL := "__popup_running_total"

func _temporary_neutral_color() -> Color:
	return Color(0.92, 0.92, 0.96)

# Next-loot bonus options added by effects (consumed when loot appears)
var _loot_options_bonus: int = 0
var _next_loot_guarantees: Dictionary = {}


func _ready() -> void:
	_loot_rng.randomize()
	_initialize_artifact_library()
	if not is_connected("winner_description_shown", Callable(self, "_on_winner_description_shown")):
		connect("winner_description_shown", Callable(self, "_on_winner_description_shown"))

func bind_totals_owner(owner: Node) -> void:
	_totals_owner = owner
	_value_label = _resolve_ui_node(_owner_node(), "%valueLabel", "valueLabel")
	_active_effect_label = _resolve_ui_node(_owner_node(), "%activeEffect", "activeEffect")
	_shown_total = total_coins
	_update_totals_label(total_coins)
	if _active_effect_label is RichTextLabel:
		(_active_effect_label as RichTextLabel).set_deferred("bbcode_enabled", true)

# ---------- Token description helper (moved up so calls resolve) ----------
func _get_token_description(token, kind: String = "") -> String:
	if token == null:
		return ""
	if token.has_method("get"):
		if kind == "active":
			var ad = token.get("activeDescription")
			if typeof(ad) == TYPE_STRING:
				var s: String = String(ad)
				if s.strip_edges() != "":
					return s
		if kind == "passive":
			var pd = token.get("passiveDescription")
			if typeof(pd) == TYPE_STRING:
				var s2: String = String(pd)
				if s2.strip_edges() != "":
					return s2
		var d = token.get("description")
		if typeof(d) == TYPE_STRING:
			var ds: String = String(d)
			if ds.strip_edges() != "":
				return ds
		var n = token.get("name")
		if typeof(n) == TYPE_STRING:
			return String(n)
	return str(token)

# ---------- Artifacts wiring ----------
func _initialize_artifact_library() -> void:
	_artifact_library.clear()
	var pool: Array = []
	if artifact_manual_pool != null and artifact_manual_pool.size() > 0:
		pool = artifact_manual_pool
	else:
		pool = _scan_artifact_directories(artifact_scan_paths)
	for art in pool:
		if art is ArtifactData:
			_artifact_library.append(art)
	if _artifact_library.is_empty():
		push_warning("CoinManager: no artifacts were loaded for the selection pool.")

func _scan_artifact_directories(paths: PackedStringArray) -> Array:
	var results: Array[ArtifactData] = []
	if paths == null:
		return results
	for raw_path in paths:
		var dir_path := str(raw_path).strip_edges()
		if dir_path == "":
			continue
		var dir := DirAccess.open(dir_path)
		if dir == null:
			push_warning("CoinManager: unable to open artifact directory %s" % dir_path)
			continue
		dir.list_dir_begin()
		while true:
			var file_name := dir.get_next()
			if file_name == "":
				break
			if dir.current_is_dir():
				continue
			if file_name.begins_with("."):
				continue
			if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
				continue
			var full_path := dir_path.path_join(file_name)
			var res := ResourceLoader.load(full_path)
			if res is ArtifactData:
				results.append(res)
		dir.list_dir_end()
	return results

func set_artifacts_order(effects: Array) -> void:
	_artifacts.clear()
	if effects != null:
		for e in effects:
			if e is ArtifactData:
				var inst := _clone_artifact(e)
				if inst != null and not _has_artifact_by_uid(_artifact_unique_id(inst)):
					_artifacts.append(inst)
	_emit_artifact_list_changed()

func register_artifact(effect: ArtifactData) -> ArtifactData:
	if effect == null:
		return null
	var uid := _artifact_unique_id(effect)
	if uid != "":
		var existing := _get_artifact_by_uid(uid)
		if existing != null:
			return existing
	var inst := _clone_artifact(effect)
	if inst == null:
		return null
	_artifacts.append(inst)
	_emit_artifact_list_changed()
	return inst

func unregister_artifact(effect: ArtifactData) -> void:
	if effect == null:
		return
	var uid := _artifact_unique_id(effect)
	for i in range(_artifacts.size() - 1, -1, -1):
		var art = _artifacts[i]
		if art == null:
			continue
		if (uid != "" and _artifact_unique_id(art) == uid) or art == effect:
			_artifacts.remove_at(i)
			break
	_emit_artifact_list_changed()

func clear_artifacts() -> void:
	_artifacts.clear()
	_emit_artifact_list_changed()

func get_active_artifacts() -> Array:
	return _artifacts.duplicate()

func queue_artifact_selection() -> void:
	if max_artifacts > 0 and _artifacts.size() >= max_artifacts:
		_artifact_selection_queued = false
		return
	_artifact_selection_queued = true
	_try_start_artifact_selection()

func _try_start_artifact_selection() -> void:
	if not _artifact_selection_queued:
		return
	if _artifact_selection_active or _loot_selection_pending or _loot_selection_forced or _target_selection_pending or _game_over_active:
		return
	var available := _collect_available_artifacts()
	if available.is_empty():
		_artifact_selection_queued = false
		return
	var options := _pick_artifact_options(available, artifact_options_count)
	if options.is_empty():
		_artifact_selection_queued = false
		return
	_artifact_selection_queued = false
	_artifact_selection_active = true
	_artifact_current_options = options.duplicate()
	_loot_selection_pending = true
	_loot_selection_forced = true
	_update_loot_skip_state()
	_notify_spin_lock_state()
	_build_loot_overlay_if_needed()
	_refresh_loot_title()
	if _loot_skip_btn != null and is_instance_valid(_loot_skip_btn):
		_loot_skip_btn.visible = false
	emit_signal("artifact_selection_started", options)
	_show_loot_overlay(-1, options, _loot_gen)

func _handle_artifact_pick(choice) -> void:
	var art: ArtifactData = null
	if choice is ArtifactData:
		art = choice
	if art == null:
		return
	var stored := register_artifact(art)
	if stored != null:
		emit_signal("artifact_acquired", stored)
	_artifact_selection_active = false
	_artifact_current_options.clear()
	_hide_loot_overlay()
	_refresh_loot_title()
	_try_start_artifact_selection()
	if not _artifact_selection_active and not _artifact_selection_queued:
		_flush_pending_loot_request()

func _flush_pending_loot_request() -> void:
	if _pending_loot_request.is_empty():
		return
	if _artifact_selection_active or _artifact_selection_queued:
		return
	var req := _pending_loot_request
	_pending_loot_request = {}
	var round_num := int(req.get("round", 0))
	var forced := bool(req.get("forced", false))
	var ctx = req.get("ctx", {})
	if ctx == null or not (ctx is Dictionary):
		ctx = {}
	_trigger_loot_choice(round_num, forced, ctx)

func _collect_available_artifacts() -> Array:
	if _artifact_library.is_empty():
		_initialize_artifact_library()
	var out: Array[ArtifactData] = []
	for art in _artifact_library:
		if art == null:
			continue
		if max_artifacts > 0 and _artifacts.size() >= max_artifacts:
			break
		var uid := _artifact_unique_id(art)
		if uid == "" or not _has_artifact_by_uid(uid):
			out.append(art)
	return out

func _pick_artifact_options(pool: Array, count: int) -> Array:
	var result: Array[ArtifactData] = []
	if pool.is_empty():
		return result
	var temp := pool.duplicate()
	var needed := clampi(count, 1, temp.size())
	for i in range(needed):
		if temp.is_empty():
			break
		var idx := int(_loot_rng.randi_range(0, temp.size() - 1))
		result.append(temp[idx])
		temp.remove_at(idx)
	return result

func _clone_artifact(effect: ArtifactData) -> ArtifactData:
	if effect == null:
		return null
	if effect is Resource:
		return (effect as Resource).duplicate(true)
	return effect

func _artifact_unique_id(effect: ArtifactData) -> String:
	if effect == null:
		return ""
	if effect.has_method("get_unique_id"):
		return str(effect.call("get_unique_id"))
	if effect.has_method("get"):
		var raw = effect.get("unique_id")
		if raw != null:
			return str(raw)
	return str(effect.get_instance_id())

func _has_artifact_by_uid(uid: String) -> bool:
	if uid.strip_edges() == "":
		return false
	for art in _artifacts:
		if art == null:
			continue
		if _artifact_unique_id(art) == uid:
			return true
	return false

func _get_artifact_by_uid(uid: String) -> ArtifactData:
	if uid.strip_edges() == "":
		return null
	for art in _artifacts:
		if art != null and _artifact_unique_id(art) == uid:
			return art
	return null

func _emit_artifact_list_changed() -> void:
	emit_signal("artifact_list_changed", _artifacts.duplicate())

func _refresh_loot_title() -> void:
	if _loot_title_label == null or not is_instance_valid(_loot_title_label):
		return
	var text := loot_title
	if _artifact_selection_active:
		var alt := artifact_loot_title.strip_edges()
		if alt != "":
			text = alt
	_loot_title_label.text = text
func reset_run() -> void:
	total_active = 0
	total_passive = 0
	total_coins = 0
	spin_index = 0
	_shown_total = 0
	_game_over_active = false
	_loot_gen += 1
	# Clear any per-token permanent offsets (future runs start from baseline)
	_token_value_offsets.clear()
	_token_tag_offsets.clear()
	_token_name_offsets.clear()
	_token_global_offset = 0
	_artifact_selection_active = false
	_artifact_selection_queued = false
	_artifact_current_options.clear()
	_pending_loot_request.clear()
	clear_artifacts()
	_refresh_loot_title()
	if is_instance_valid(_bank_tween):
		_bank_tween.kill()
	_bank_tween = null
	_update_totals_label(total_coins)
	_update_round_and_deadline_labels()
	_update_spin_counters(true)
	_hide_game_over()
	_effect_targets.clear()
	_kill_active_highlight()
	_current_effect_source = null
	_hide_loot_overlay()
	emit_signal("game_reset")

# ---------- Spin sequence ----------
func begin_spin() -> void:
	if _loot_selection_pending or _loot_selection_forced or _target_selection_pending:
		return
	_clear_temp_value_meta_all()
	# Increment the run spin index and refresh UI immediately on button press
	spin_index += 1
	_update_spin_counters(false)

	# Per-spin highlight scope: clear any recorded effect targets/highlights from prior spins
	_effect_targets.clear()
	_kill_active_highlight()

func _clear_temp_value_meta_all() -> void:
	var arr := _get_inventory_array()
	if arr is Array:
		for token in arr:
			_reset_temp_meta(token)

func _reset_temp_meta(token) -> void:
	_set_token_temp_meta(token, 0.0)

func _update_token_temp_meta_from_contrib(token, contrib: Dictionary, is_temp: bool) -> void:
	if token == null or contrib == null:
		return
	if not is_temp:
		_reset_temp_meta(token)
		return
	var base_val := int(contrib.get("base", 0))
	var current_val := _compute_value(contrib)
	_set_token_temp_meta(token, float(current_val - base_val))

func can_begin_spin() -> bool:
	return not (_loot_selection_pending or _loot_selection_forced or _target_selection_pending)

func _notify_spin_lock_state(ctx: Dictionary = {}) -> void:
	var sr = null
	if ctx != null and ctx.has("spin_root"):
		sr = ctx["spin_root"]
	if sr == null:
		var scene := get_tree().current_scene
		if scene != null:
			sr = scene.find_child("spinRoot", true, false)
	if sr != null and sr is Object and (sr as Object).has_method("_apply_spin_button_state"):
		sr.call_deferred("_apply_spin_button_state")

func _set_token_temp_meta(token, delta: float) -> void:
	if token == null or not (token as Object).has_method("set_meta"):
		return
	var color := _temporary_neutral_color()
	if delta > 0.001:
		color = temporary_gain_color
	elif delta < -0.001:
		color = temporary_loss_color
	if (token as Object).has_method("set_meta"):
		token.set_meta(TEMP_META_DELTA, delta)
		token.set_meta(TEMP_META_COLOR, color)

func play_spin(winner, neighbors: Array, extra_ctx := {}) -> Dictionary:

	var ctx: Dictionary = {
		"winner": winner,
		"neighbors": neighbors,
		"spin_index": spin_index,
		"rng": _mk_rng()
	}
	for k in extra_ctx.keys():
		ctx[k] = extra_ctx[k]

	# Provide inventory tokens for abilities that depend on board/inventory counts.
	ctx["board_tokens"] = _get_inventory_array()
	_value_label_defer_depth += 1

	# Ensure a function-scope result is always available
	var result: Dictionary = {}
	var defer_winner_active: bool = true
	var dval = ctx.get("defer_winner_active")
	if dval != null:
		defer_winner_active = bool(dval)

	# Resolve total passive-trigger delay (ctx override -> member if present -> fallback to base or 0.8)
	var passive_trigger_delay_total: float = base_show_delay_sec
	var ptd_ctx: Variant = ctx.get("passive_trigger_delay_sec")
	if ptd_ctx != null:
		passive_trigger_delay_total = float(ptd_ctx)
	else:
		var ptd_member: Variant = get("passive_trigger_delay_sec")
		if ptd_member != null:
			passive_trigger_delay_total = float(ptd_member)
		else:
			passive_trigger_delay_total = max(base_show_delay_sec, 0.8)

	if debug_spin:
		print("[Delays] winner=", show_winner_desc_delay_sec,
			" base=", base_show_delay_sec,
			" between=", between_tokens_delay_sec,
			" step=", step_delay_sec,
			" passive_total=", passive_trigger_delay_sec,
			" active_pause=", active_desc_pause_sec,
			" bank_anim=", bank_anim_duration_sec,
			" loot_post=", loot_post_spin_delay,
			" Engine.ts=", Engine.time_scale)
		print("\n[Spin] ===== spin #", spin_index + 1, " =====")
	emit_signal("spin_sequence_started", ctx)

	var winner_desc: String = _get_token_description(winner, "active")
	emit_signal("winner_description_shown", winner, winner_desc)
	await _pause(show_winner_desc_delay_sec)

	var offsets: Array = [-2, -1, 0, 1, 2]
	var norder: Array = [-2, -1, 1, 2]
	var contribs: Array = []
	var baseline_snapshot: Array = []
	var winner_idx: int = -1

	for off in offsets:
		var token: Object = null
		if off == 0:
			token = winner
		else:
			var idx: int = -1
			for j in range(norder.size()):
				if norder[j] == off:
					idx = j
					break
			if idx >= 0 and idx < neighbors.size():
				token = neighbors[idx]

		var kind: String
		if off == 0:
			kind = "active"
		else:
			kind = "passive"

		var base_val: int = _safe_int(token, "value", 0)
		var c: Dictionary = _mk_contrib(token, kind, base_val, off)
		contribs.append(c)
		if off == 0:
			winner_idx = contribs.size() - 1
		if debug_spin:
			var token_str: String = ""
			if token != null and token.has_method("get"):
				var name_val = token.get("name")
				if typeof(name_val) == TYPE_STRING:
					token_str = String(name_val)
				else:
					token_str = str(token)

			print("[Spin] Slot offset ", off, " -> token=", token_str, " kind=", kind, " base=", base_val)

	baseline_snapshot = _snapshot_baseline_contribs(contribs)
	# Provide contribs for reactive abilities (e.g., neighbor checks)
	ctx["__last_contribs"] = contribs
	# winner active steps (self) deferred here; winner global active (affect others) collected later
	var deferred_winner_self_steps: Array = []

	# Per-token sequence in strict order:
	# 1) base popup; 2) token passive; 3) artifacts; (winner active deferred)
	for i in range(contribs.size()):
		var c: Dictionary = contribs[i]
		var effect_token = c.get("token")
		if effect_token != null:
			var slot_ctrl := _slot_from_ctx(ctx, int(c.offset))
			if slot_ctrl is Control:
				_register_token_control(effect_token, slot_ctrl)
			_reset_effect_tracking_for_token(effect_token)
		emit_signal("token_sequence_started", i, c.offset, c)

		# 1) Base value popup + shake
		var base_value: int = _compute_value(c)
		emit_signal("token_value_shown", i, c.offset, base_value, c)
		_play_counting_popup(ctx, c, 0, base_value, true)
		if debug_spin:
			print("[Step] Base show offset=", c.offset, " value=", base_value)
			await _pause(base_show_delay_sec)

		# 2) Token steps (token-defined + abilities Active During Spin)
		var token_steps_base: Array = _collect_token_description_steps(ctx, c)

		# NEW: split ability steps into immediate vs deferred (winner_only on winner)
		var ab_parts: Dictionary = _collect_ability_spin_steps(ctx, c, winner)  # {immediate:[], deferred:[]}
		var now_steps: Array = []
		now_steps.append_array(token_steps_base)
		now_steps.append_array(ab_parts.get("immediate", []))

		# Only extend base->passive gap if this contrib is passive AND will apply steps now.
		var will_apply_now: bool = not (int(c.offset) == 0 and defer_winner_active)
		if c.kind == "passive" and will_apply_now and (not now_steps.is_empty() or not ab_parts.get("deferred", []).is_empty()):
			var extra_wait: float = max(0.0, passive_trigger_delay_total - base_show_delay_sec)
			if extra_wait > 0.0:
				await _pause(extra_wait)

		# Defer only winner_only ability steps for the winner; everything else applies now
		if c.offset == 0 and defer_winner_active:
			var def_arr: Array = ab_parts.get("deferred", [])
			for s in def_arr:
				var sk: String = String(s.get("kind", ""))
				if sk == "add" or sk == "mult":
					deferred_winner_self_steps.append(s)
				if debug_spin:
					print("  [Defer] Winner self step deferred: ", s)
			# Apply 'now' steps immediately (winner token steps + non-winner_only ability steps)
			if not now_steps.is_empty():
				await _apply_steps_now(i, c, now_steps, ctx, c.token)
		else:
			# For non-winner or when not deferring, apply both immediate and deferred
			var apply_steps: Array = []
			apply_steps.append_array(now_steps)
			apply_steps.append_array(ab_parts.get("deferred", []))
			if not apply_steps.is_empty():
				await _apply_steps_now(i, c, apply_steps, ctx, c.token)

		# 3) Artifacts
		if not _is_contrib_zero_replaced(c):
			for art in _artifacts:
				if not (art is ArtifactData):
					continue
				if not art.applies(ctx, c):
					continue
				var steps_from_art: Array = art.build_steps(ctx, c)
				if debug_spin and not steps_from_art.is_empty():
					print("[Artifact] ", art, " steps for offset ", c.offset, ": ", steps_from_art.size())
				await _apply_steps_now(i, c, steps_from_art, ctx, art)

		var tmp_final: int = _finalize_contrib(c)
		emit_signal("token_sequence_finished", i, c.offset, tmp_final, c)
		if debug_spin:
			print("[Spin] Interim finalize offset=", c.offset, " val=", tmp_final)
		_restore_slot_modulate(ctx, int(c.offset))
		var __bt_t0: int = 0
		if debug_spin:
			__bt_t0 = Time.get_ticks_msec()
		await _pause(between_tokens_delay_sec)
		if debug_spin:
			var __bt_t1: int = Time.get_ticks_msec()
			print("[BetweenTokens] waited=", float(__bt_t1 - __bt_t0) / 1000.0, "s; cfg=", between_tokens_delay_sec, " Engine.ts=", Engine.time_scale)

	# After all five run, apply the winner's final active to all matching tokens at once
	if winner != null:
		var global_active_steps: Array = _collect_winner_active_global_steps(ctx, winner, contribs)
		if debug_spin:
			print("[Final-Active] Winner global steps: ", global_active_steps.size())
		# Collect winner ability commands that need post-shake execution (e.g., Mint visuals, Hustler permanent add)
		var __board_cmds := _collect_winner_ability_commands(ctx, contribs, winner)
		var board_visual_cmds: Array = []
		var post_shake_cmds: Array = []
		var had_perm_cmd := false
		var had_spawn_cmd := false
		for cmd in __board_cmds:
			if typeof(cmd) != TYPE_DICTIONARY:
				continue
			var op := String((cmd as Dictionary).get("op", ""))
			if op == "replace_board_tag" or op == "replace_board_empties":
				board_visual_cmds.append(cmd)
			elif op == "replace_all_empties":
				post_shake_cmds.append(cmd)
				ctx["__ran_replace_all_empties"] = true
			elif op == "permanent_add":
				post_shake_cmds.append(cmd)
				had_perm_cmd = true
			elif op == "spawn_token_in_inventory":
				post_shake_cmds.append(cmd)
				had_spawn_cmd = true
		# Do not scale self-target permanent_add here; visuals will display per-matching token separately
		# Stash board visual commands in ctx for the broadcast phase to run right after the active label shake
		var need_board_phase := not board_visual_cmds.is_empty() or not post_shake_cmds.is_empty()
		if not board_visual_cmds.is_empty():
			ctx["__board_visual_cmds"] = board_visual_cmds
			ctx["__ran_replace_board_tag"] = true
		if not post_shake_cmds.is_empty():
			ctx["__post_shake_cmds"] = post_shake_cmds
			if had_perm_cmd:
				ctx["__ran_permanent_add"] = true
			if had_spawn_cmd:
				ctx["__ran_spawn_inventory"] = true
		# Run the post-shake phase if there are any winner global steps OR any post-shake/board-visual commands
		if need_board_phase or not global_active_steps.is_empty():
			await _apply_global_steps_broadcast(global_active_steps, contribs, ctx, winner)
	await _pause(active_desc_pause_sec)
	# Then apply the winner's own deferred active to itself (shake description first + pause)
	if defer_winner_active and winner_idx >= 0 and deferred_winner_self_steps.size() > 0:
		var cw: Dictionary = contribs[winner_idx]
		_shake_active_effect_label()

		if debug_spin:
			print("[Final-Active] Applying deferred winner self steps: ", deferred_winner_self_steps.size())
		await _apply_steps_now(winner_idx, cw, deferred_winner_self_steps, ctx, winner)

	# Execute winner ability commands after spin steps but before final totals
	# These mutate inventory for future spins (e.g., replace lowest with Coin)
	var _cmds := _collect_winner_ability_commands(ctx, contribs, winner)
	if _cmds is Array and not _cmds.is_empty():
		# Filter out early-run inventory ops
		var skip_empties := bool(ctx.get("__ran_replace_all_empties", false))
		var skip_perm := bool(ctx.get("__ran_permanent_add", false))
		var skip_board := bool(ctx.get("__ran_replace_board_tag", false))
		var skip_spawn := bool(ctx.get("__ran_spawn_inventory", false))
		var late: Array = []
		for cmd in _cmds:
			if typeof(cmd) != TYPE_DICTIONARY:
				continue
			var op := String((cmd as Dictionary).get("op", ""))
			if skip_empties and op == "replace_all_empties":
				continue
			if skip_perm and op == "permanent_add":
				continue
				if skip_board and (op == "replace_board_tag" or op == "replace_board_empties"):
					continue
				if skip_spawn and op == "spawn_token_in_inventory":
					continue
			late.append(cmd)
		if not late.is_empty():
			if debug_spin:
				print("[Commands] Found ", late.size(), " command(s). Executing...")
			await _execute_ability_commands(late, ctx, contribs, winner)

		# Execute any commands enqueued by reactive abilities during steps (e.g., on_value_changed hooks)
		var pend = ctx.get("__pending_commands", [])
		if pend is Array and not (pend as Array).is_empty():
			if debug_spin:
				print("[Commands] Executing ", (pend as Array).size(), " pending reactive command(s)...")
			await _execute_ability_commands(pend, ctx, contribs, null)
			ctx["__pending_commands"] = []

	# Finalize contributions and totals after all commands resolve
	for k in range(contribs.size()):
		var ck: Dictionary = contribs[k]
		ck.meta["final"] = _finalize_contrib(ck)
		if debug_spin:
			print("[Spin] Final offset=", ck.offset, " => ", ck.meta["final"])

	var active_total: int = 0
	var passive_total: int = 0
	for c in contribs:
		var fin: int = 0
		if (c.meta as Dictionary).has("final"):
			fin = int((c.meta as Dictionary).get("final"))
		if c.kind == "active":
			active_total += fin
		else:
			passive_total += fin

	total_active += active_total
	total_passive += passive_total
	var spin_total: int = active_total + passive_total
	total_coins += spin_total

	if _value_label_defer_depth > 0:
		_value_label_defer_depth -= 1
	_update_totals_label(total_coins, true)
	_update_spin_counters(false)

	# Build result dictionary without multi-line literal
	result = {}
	result["active_total"] = active_total
	result["passive_total"] = passive_total
	result["spin_total"] = spin_total
	result["run_total"] = total_coins
	result["contributions"] = contribs
	result["baseline"] = baseline_snapshot
	result["context"] = ctx
	if debug_spin:
		print("[Totals] active=", active_total, " passive=", passive_total, " spin_total=", result["spin_total"], " run_total=", total_coins)
	emit_signal("spin_totals_ready", result)


	if enable_game_over:
		var spr: int = max(spins_per_round, 1)
		var remainder: int = spin_index % spr
		if remainder == 0:
			var round_num: int = int(spin_index / spr)
			_handle_end_of_round(round_num)
			_update_spin_counters()

	return result
			
# Apply a list of steps to a contrib with shake/popup per step
func _apply_steps_now(i: int, c: Dictionary, steps: Array, ctx: Dictionary, source_token: Object = null) -> void:
	for step in steps:
		var stepn: Dictionary = _normalize_step(step)
		# Ability filters can cancel or mutate the step
		var filtered = _filter_step_for_contrib(ctx, stepn, source_token, c)
		if typeof(filtered) != TYPE_DICTIONARY:
			if debug_spin:
				print("	[Filter] step canceled for offset=", c.offset, " src=", stepn.get("source", "unknown"))
			continue
		stepn = filtered

		var step_source := String(stepn.get("source", ""))
		var prev_effect_source: Variant = _current_effect_source
		var is_effect_step := source_token != null and step_source.begins_with("ability:")
		if is_effect_step:
			_current_effect_source = source_token

		var prev_val: int = _compute_value(c)
		if debug_spin:
			print("	[Apply] offset=", c.offset, " kind=", stepn.get("kind"), " +", stepn.get("amount", 0), " x", stepn.get("factor", 1.0), " src=", stepn.get("source", "unknown"))
		_apply_step(c, stepn)
		var base_new_val: int = _compute_value(c)
		_invoke_on_value_changed(ctx, source_token, c, prev_val, base_new_val, stepn)
		var new_val: int = _compute_value(c)
		var delta := new_val - prev_val
		var shake_mag := 0.0
		if delta >= screen_shake_heavy_threshold:
			shake_mag = screen_shake_heavy_intensity
		elif delta >= screen_shake_moderate_threshold:
			shake_mag = screen_shake_moderate_intensity
		elif delta >= screen_shake_light_threshold:
			shake_mag = screen_shake_light_intensity

		# Emit signals so UI/listeners refresh immediately
		emit_signal("token_step_applied", i, c.offset, stepn, new_val, c)
		emit_signal("token_value_shown", i, c.offset, new_val, c)

		# Update inline slot value if available
		var slot := _slot_from_ctx(ctx, int(c.offset))
		if slot != null:
			var si := slot.get_node_or_null("slotItem")
			if si != null and si.has_method("set_value"):
				si.call_deferred("set_value", new_val)

		# Popup + shake
		_play_counting_popup(ctx, c, prev_val, new_val, false, stepn)

		if shake_mag > 0.0:
			if not _is_contrib_zero_replaced(c):
				_shake_slot_for_contrib(ctx, c)
			await _apply_screen_shake(shake_mag, screen_shake_duration)

		if is_effect_step and source_token != null:
			var target_token = c.get("token")
			if target_token != null:
				if source_token != target_token:
					_register_effect_target(source_token, target_token)
					_current_effect_source = prev_effect_source

		var reason := "%s:%s" % [String(stepn.get("source", "unknown")), String(stepn.get("kind", ""))]
		var destroyed_this_step := _maybe_replace_contrib_with_empty(ctx, c, prev_val, new_val, reason)
		await _pause(step_delay_sec)
		if destroyed_this_step:
			break

func _is_contrib_zero_replaced(contrib: Dictionary) -> bool:
	if contrib == null:
		return false
	var meta = contrib.get("meta", {})
	if meta is Dictionary:
		return bool((meta as Dictionary).get(META_ZERO_REPLACED, false))
	return false

func _maybe_replace_contrib_with_empty(ctx: Dictionary, contrib: Dictionary, prev_val: int, new_val: int, reason: String) -> bool:
	if contrib == null:
		return false
	if new_val > 0:
		return false
	var meta_variant = contrib.get("meta", {})
	var meta: Dictionary = meta_variant if meta_variant is Dictionary else {}
	if not (meta is Dictionary):
		meta = {}
		contrib["meta"] = meta
	if bool(meta.get(META_ZERO_REPLACED, false)):
		return false
	var empty_path := String(empty_token_path).strip_edges()
	if empty_path == "":
		if debug_spin:
			print("[ZeroReplace] empty_token_path is empty; cannot replace token at offset ", contrib.get("offset", 0))
		return false
	var offset := int(contrib.get("offset", 0))
	var slot := _slot_from_ctx(ctx, offset)
	var replacement := _replace_token_at_offset(ctx, offset, empty_path, ZERO_REPLACEMENT_VALUE, false, contrib.get("token"))
	if replacement == null:
		return false
	meta[META_ZERO_REPLACED] = true
	meta[META_ZERO_REASON] = reason
	contrib["token"] = replacement
	contrib["base"] = ZERO_REPLACEMENT_VALUE
	contrib["delta"] = 0
	contrib["mult"] = 1.0
	if debug_spin:
		print("[ZeroReplace] offset=", offset, " prev=", prev_val, " new=", new_val, " reason=", reason)
	return true

func _apply_screen_shake(magnitude: float, duration: float) -> void:
	if magnitude <= 0.0 or duration <= 0.0:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var rng := _mk_rng()
	var steps := int(max(2, duration / 0.05))
	var step_time := duration / float(steps)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var camera := viewport.get_camera_2d()
	if camera != null:
		var original_offset := camera.offset
		for i in range(steps):
			var off := Vector2(rng.randf_range(-magnitude, magnitude), rng.randf_range(-magnitude, magnitude))
			var seg := tween.tween_property(camera, "offset", original_offset + off, step_time)
			seg.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var reset := tween.tween_property(camera, "offset", original_offset, 0.1)
		reset.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await tween.finished
		camera.offset = original_offset
		return
	var fallback := get_tree().current_scene
	if fallback == null or not (fallback is CanvasItem):
		fallback = get_tree().root.get_node_or_null("mainUI")
	if fallback is CanvasItem:
		var canvas: CanvasItem = fallback as CanvasItem
		var original_pos: Vector2 = canvas.position
		canvas.position = original_pos
		for i in range(steps):
			var off := Vector2(rng.randf_range(-magnitude, magnitude), rng.randf_range(-magnitude, magnitude))
			var seg := tween.tween_property(canvas, "position", original_pos + off, step_time)
			seg.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var reset := tween.tween_property(canvas, "position", original_pos, 0.1)
		reset.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await tween.finished
		canvas.position = original_pos
		return
	tween.kill()
func _shake_slot_for_contrib(ctx: Dictionary, contrib: Dictionary) -> void:
	if ctx == null or contrib == null:
		return
	var off := int(contrib.get("offset", 0))
	var slot := _slot_from_ctx(ctx, off)
	if slot != null:
		_shake_slot(slot)

# NEW: Apply one global step across multiple tokens simultaneously
func _apply_global_step_parallel(step: Dictionary, contribs: Array, indices: Array, ctx: Dictionary) -> void:
	var prev_effect_source: Variant = _current_effect_source
	# Snapshot previous values
	var prev_vals: Array[int] = []
	prev_vals.resize(indices.size())
	var shake_by_index: Dictionary = {}
	for k in range(indices.size()):
		var idx := int(indices[k])
		var c: Dictionary = contribs[idx]
		prev_vals[k] = _compute_value(c)
	# Apply step to all targets (mutate first, then animate/signals)
	for k in range(indices.size()):
		var idx := int(indices[k])
		var c: Dictionary = contribs[idx]
		if _is_contrib_zero_replaced(c):
			if debug_spin:
				print("    [Apply-Parallel] offset=", c.get("offset", c.offset), " skipped (already replaced)")
			continue
		if debug_spin:
			print("    [Apply-Parallel] offset=", c.offset, " kind=", step.get("kind"), " +", step.get("amount", 0), " x", step.get("factor", 1.0), " src=", step.get("source", "unknown"))
		var prev_val := _compute_value(c)
		_apply_step(c, step)
		var base_new_val := _compute_value(c)
		_invoke_on_value_changed(ctx, null, c, prev_val, base_new_val, step)
		var new_val := _compute_value(c)
		var delta := new_val - prev_val
		var shake_mag := 0.0
		if delta >= screen_shake_heavy_threshold:
			shake_mag = screen_shake_heavy_intensity
		elif delta >= screen_shake_moderate_threshold:
			shake_mag = screen_shake_moderate_intensity
		elif delta >= screen_shake_light_threshold:
			shake_mag = screen_shake_light_intensity
		if shake_mag > 0.0:
			shake_by_index[idx] = shake_mag

	# Emit and update visuals for all targets
	for k in range(indices.size()):
		var idx := int(indices[k])
		var c: Dictionary = contribs[idx]
		if _is_contrib_zero_replaced(c):
			continue
		var new_val := _compute_value(c)

		emit_signal("token_step_applied", idx, c.offset, step, new_val, c)
		emit_signal("token_value_shown", idx, c.offset, new_val, c)

		var slot := _slot_from_ctx(ctx, int(c.offset))
		if slot != null:
			var si := slot.get_node_or_null("slotItem")
			if si != null and si.has_method("set_value"):
				si.call_deferred("set_value", new_val)

	# Kick popups for all targets in sync
	for k in range(indices.size()):
		var idx := int(indices[k])
		var c: Dictionary = contribs[idx]
		if _is_contrib_zero_replaced(c):
			continue
		_play_counting_popup(ctx, c, prev_vals[k], _compute_value(c), false, {})
		var shake_mag := float(shake_by_index.get(idx, 0.0))
		if shake_mag > 0.0:
			_shake_slot_for_contrib(ctx, c)
			await _apply_screen_shake(shake_mag, screen_shake_duration)

	# Replace any tokens that hit zero after the parallel step
	for k in range(indices.size()):
		var idx := int(indices[k])
		var c: Dictionary = contribs[idx]
		if _is_contrib_zero_replaced(c):
			continue
		var reason := "global:%s" % String(step.get("source", "unknown"))
		_maybe_replace_contrib_with_empty(ctx, c, int(prev_vals[k]), _compute_value(c), reason)

	# Shared delay once per global step (not per token)
	await _pause(step_delay_sec)
	_current_effect_source = prev_effect_source

# Winner final active hooks
# Winner final active hooks (only abilities with winner_only=true contribute here)
func _collect_winner_active_global_steps(ctx: Dictionary, winner, contribs: Array) -> Array:
	var out: Array = []
	if winner == null:
		return out

	# Winner token: custom global steps during final phase (author-provided; winner_only only)
	if winner.has_method("get"):
		var abilities = winner.get("abilities")
		if abilities is Array:
			for ab in abilities:
				if ab == null:
					continue
				if not _ability_is_active_during_spin(ab):
					continue
				if not _ability_winner_only(ab):
					continue
				if (ab as Object).has_method("build_final_steps"):
					var arr2 = ab.build_final_steps(ctx, contribs, winner)
					if arr2 is Array:
						for s2 in arr2:
							out.append(_normalize_global_step(s2))

	# Winner token: also allow build_final_steps directly on the token (opt-in by authoring)
	if winner.has_method("build_final_steps"):
		var arr3 = winner.build_final_steps(ctx, contribs)
		if arr3 is Array:
			for s3 in arr3:
				out.append(_normalize_global_step(s3))

	# Legacy synthetic fallback (winner_only only): synthesize steps from fields
	if winner.has_method("get"):
		var abilities2 = winner.get("abilities")
		if abilities2 is Array:
			for ab in abilities2:
				if ab == null:
					continue
				if not _ability_is_active_during_spin(ab):
					continue
				if not _ability_winner_only(ab):
					continue
				# Avoid double-applying effects: if an ability declares build_commands (e.g., permanent_add),
				# do not synthesize an "add/mult" spin step from its amount/factor.
				if (ab as Object).has_method("build_commands"):
					continue

				var tk := _ability_target_kind(ab).to_lower()
				var amt := int(max(0, _ability_amount(ab)))
				var fac := float(max(0.0, _ability_factor(ab)))
				var kind_s := ""
				if fac > 0.0 and abs(fac - 1.0) > 0.0001:
					kind_s = "mult"
				elif amt != 0:
					kind_s = "add"
				if kind_s == "":
					continue

				var src := "ability:" + _ability_id_or_class(ab)
				var desc := _ability_desc(ab, fac, amt, winner)

				# Use a local lambda assigned to a variable (OK in GDScript 4)
				var append_step_for_offset := func(off: int) -> void:
					var step := {
						"kind": kind_s,
						"amount": amt if kind_s == "add" else 0,
						"factor": fac if kind_s == "mult" else 1.0,
						"desc": desc,
						"source": src,
					}
					if off == 0:
						step["target_kind"] = "self"
						step["target_offset"] = 0
					else:
						step["target_kind"] = "offset"
						step["target_offset"] = off
					out.append(_normalize_global_step(step))

				match tk:
					"self", "winner", "middle":
						append_step_for_offset.call(0)
					"neighbors", "adjacent":
						for c in contribs:
							var off := int(c.get("offset", 99))
							if abs(off) == 1:
								append_step_for_offset.call(off)
					"left":
						append_step_for_offset.call(-1)
					"right":
						append_step_for_offset.call(1)
					"edges", "outer":
						for c in contribs:
							var off := int(c.get("offset", 99))
							if abs(off) == 2:
								append_step_for_offset.call(off)
					"offset":
						append_step_for_offset.call(int(ab.get("target_offset", 0)))
					"tag":
						for c in contribs:
							if _token_has_tag(c.get("token"), String(ab.get("target_tag", ""))):
								append_step_for_offset.call(int(c.get("offset", 99)))
					"name":
						for c in contribs:
							if _token_name(c.get("token")) == String(ab.get("target_name", "")):
								append_step_for_offset.call(int(c.get("offset", 99)))
					"active":
						for c in contribs:
							if String(c.get("kind", "")).to_lower() == "active":
								append_step_for_offset.call(int(c.get("offset", 99)))
					"passive":
						for c in contribs:
							if String(c.get("kind", "")).to_lower() == "passive":
								append_step_for_offset.call(int(c.get("offset", 99)))
					"any", "all":
						for c in contribs:
							append_step_for_offset.call(int(c.get("offset", 99)))
					_:
						append_step_for_offset.call(0)

	if debug_spin and not out.is_empty():
		print("[Final-Active] Collected winner global step dicts: ", out.size())
	return out
	
func _global_step_matches(step: Dictionary, contrib: Dictionary, source_token) -> bool:
	var off := int(contrib.get("offset", 99))
	var tk := String(step.get("target_kind", "any")).to_lower()

	match tk:
		"any", "all":
			return true
		"self", "winner":
			return contrib.get("token") == source_token
		"others", "not_self":
			return contrib.get("token") != source_token
		"active":
			return String(contrib.get("kind", "")).to_lower() == "active"
		"passive":
			return String(contrib.get("kind", "")).to_lower() == "passive"
		"neighbors", "adjacent":
			return abs(off) == 1
		"left":
			return off == -1
		"right":
			return off == 1
		"edges", "outer":
			return abs(off) == 2
		"center", "middle":
			return off == 0
		"offset":
			return off == int(step.get("target_offset", 0))
		"tag":
			return _token_has_tag(contrib.get("token"), String(step.get("target_tag", "")))
		"name":
			return _token_name(contrib.get("token")) == String(step.get("target_name", ""))
		_:
			# Be permissive by default to avoid silently dropping authored steps.
			return true

# ---------- Counting popup ----------
func _play_counting_popup(ctx: Dictionary, contrib: Dictionary, from_val: int, to_val: int, is_base: bool, step_info: Dictionary = {}, prev_actual_val: Variant = null) -> void:
	var env := _ensure_popup(ctx, contrib)
	if env.is_empty():
		return
	var popup := env["popup"] as Control
	var slot := env["slot"] as Control
	var prev_display_total := 0.0
	if popup.has_meta(POPUP_META_TOTAL):
		prev_display_total = float(popup.get_meta(POPUP_META_TOTAL, 0.0))
	else:
		popup.set_meta(POPUP_META_TOTAL, 0.0)
	var actual_prev := float(from_val)
	if prev_actual_val != null:
		actual_prev = float(prev_actual_val)
	if is_base:
		prev_display_total = 0.0
		popup.set_meta(POPUP_META_TOTAL, prev_display_total)

	var base_mod := slot.modulate
	var fx := get_tree().create_tween()
	popup.set_meta("fx_tween", fx)
	if is_base:
		fx.tween_property(slot, "modulate", Color(base_mod.r, base_mod.g, base_mod.b, 0.85), 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fx.chain().tween_property(slot, "modulate", base_mod, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		fx.tween_property(slot, "modulate", Color(base_mod.r, base_mod.g, base_mod.b, 0.90), 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		fx.chain().tween_property(slot, "modulate", base_mod, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	var fx2 := get_tree().create_tween()
	fx2.set_parallel(true)
	popup.scale = Vector2.ONE
	fx2.tween_property(popup, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fx2.chain().tween_property(popup, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	var rng := _mk_rng()
	var shake_target: Node = slot.get_node_or_null("slotItem")
	if shake_target == null:
		shake_target = slot
	var orig_pos: Vector2 = (shake_target as CanvasItem).position
	var shake := get_tree().create_tween()
	popup.set_meta("shake_tween", shake)
	var shakes := 3
	var strength: float = 8.0
	for i in range(shakes):
		var offv := Vector2(rng.randf_range(-strength, strength), rng.randf_range(-strength, strength))
		shake.tween_property(shake_target, "position", orig_pos + offv, 0.03).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	shake.tween_property(shake_target, "position", orig_pos, 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	var actual_change := float(to_val) - actual_prev
	var new_display_total := prev_display_total + actual_change
	var delta_display = abs(new_display_total - prev_display_total)
	var count_dur: float = clamp(0.06 + delta_display * 0.015, 0.12, 0.30)

	var ct := get_tree().create_tween()
	popup.set_meta("count_tween", ct)
	var color := _temporary_neutral_color()
	if not is_base and step_info is Dictionary and _is_step_temporary(step_info):
		if actual_change > 0.0:
			color = temporary_gain_color
		elif actual_change < 0.0:
			color = temporary_loss_color
	_apply_popup_glow(popup, color)
	popup.set_meta(POPUP_META_TOTAL, new_display_total)
	var call := Callable(self, "_set_counting_text").bind(env["label"], color)
	ct.tween_method(call, prev_display_total, new_display_total, count_dur).set_trans(Tween.TRANS_LINEAR)


func _apply_popup_glow(popup: Control, color: Color) -> void:
	if popup == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	var glow_alpha = clamp(color.a + 0.35, 0.0, 1.0)
	style.shadow_color = Color(color.r, color.g, color.b, glow_alpha)
	style.shadow_size = 12
	style.shadow_offset = Vector2.ZERO
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	if popup.has_theme_stylebox_override("panel"):
		popup.remove_theme_stylebox_override("panel")
	if popup.has_theme_stylebox_override("normal"):
		popup.remove_theme_stylebox_override("normal")
	popup.add_theme_stylebox_override("panel", style)
	popup.add_theme_stylebox_override("normal", style)

func _set_counting_text(v: float, target: Node, color: Color) -> void:
	if target == null:
		return
	var diff := int(round(v))
	var sign := "+" if diff >= 0 else ""
	var t := "%s%d%s" % [sign, diff, _gold_bbcode()]
	if target is RichTextLabel:
		var rtl := target as RichTextLabel
		rtl.bbcode_enabled = true
		var color_code: String = color.to_html(false)
		rtl.bbcode_text = "[color=%s]%s[/color]" % [color_code, t]
	elif target is Label:
		var lbl := target as Label
		lbl.add_theme_color_override("font_color", color)
		lbl.text = t.replace(_gold_bbcode(), "G")
	else:
		if target.has_method("set"):
			target.set("text", t.replace(_gold_bbcode(), "G"))

func _ensure_popup(ctx: Dictionary, contrib: Dictionary) -> Dictionary:
	var slot := _slot_from_ctx(ctx, int(contrib.offset))
	if slot == null:
		return {}
	var popup := slot.get_node_or_null("FloatingPopup")
	if popup == null:
		var fls: PackedScene = floating_label_scene
		if fls == null and ctx.has("floating_label_scene"):
			var alt = ctx.get("floating_label_scene")
			if alt is PackedScene:
				fls = alt
		if fls != null:
			popup = fls.instantiate() as Control
		else:
			popup = Control.new()
			popup.custom_minimum_size = Vector2(120, 48)
			var lbl := RichTextLabel.new()
			lbl.name = "valueLabel"
			lbl.bbcode_enabled = true
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
			popup.add_child(lbl)
		popup.name = "FloatingPopup"
		slot.add_child(popup)
	if popup is CanvasItem:
		(popup as CanvasItem).z_index = 1

	var ctrl := popup as Control
	ctrl.position = Vector2(slot.size.x - ctrl.size.x, 15)
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.call_deferred("set_position", Vector2(slot.size.x - ctrl.size.x, 15))
	ctrl.call_deferred("set", "pivot_offset", ctrl.size * 0.5)
	if not popup.has_meta(POPUP_META_TOTAL):
		popup.set_meta(POPUP_META_TOTAL, 0.0)

	# Robust label acquisition/fallback
	var label := popup.get_node_or_null("labelMarginContainer/labelContainer/popupValueLabel")
	if label == null:
		label = popup.get_node_or_null("valueLabel")
	if label == null:
		var lbl2 := Label.new()
		lbl2.name = "valueLabel"
		lbl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		popup.add_child(lbl2)
		label = lbl2

	return {
		"slot": slot,
		"popup": popup,
		"label": label
	}

func _restore_slot_modulate(ctx: Dictionary, offset: int) -> void:
	var slot := _slot_from_ctx(ctx, offset)
	if slot == null:
		return
	var base_mod := slot.modulate
	var tween := get_tree().create_tween()
	tween.tween_property(slot, "modulate", Color(base_mod.r, base_mod.g, base_mod.b, 1.0), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _slot_from_ctx(ctx: Dictionary, offset: int) -> Control:
	if not ctx.has("slot_map"):
		return null
	var sm = ctx["slot_map"]
	if not (sm is Dictionary):
		return null
	var node = (sm as Dictionary).get(offset)
	if node is Control:
		return node as Control
	return null

# ---------- Ante / Game Over ----------
func _handle_end_of_round(round_num: int) -> void:
	while _target_selection_pending:
		await get_tree().process_frame
	var requirement: int = _get_requirement_for_round(round_num)
	var starting_coins: int = total_coins
	var can_pay := starting_coins >= requirement
	var spin_root := _resolve_spin_root()
	var spin_btn_state := true
	if spin_root != null and spin_root.has_method('_is_spin_button_enabled'):
		spin_btn_state = bool(spin_root.call('_is_spin_button_enabled'))
	if spin_root != null and spin_root.has_method('_set_spin_button_enabled'):
		spin_root.call('_set_spin_button_enabled', false)
	await _pause(2.0)
	var coins_after := await _play_round_pay_animation(round_num, starting_coins, requirement, can_pay, deduct_on_pay)

	if deduct_on_pay:
		total_coins = coins_after
		_update_totals_label(total_coins, true)
	if can_pay:
		emit_signal("round_ended", round_num, requirement, true)
		_update_spin_counters()
		_trigger_loot_choice(round_num)
	else:
		emit_signal("round_ended", round_num, requirement, false)
		_trigger_game_over(round_num, requirement)
		_update_spin_counters()

	if spin_root != null and spin_root.has_method('_set_spin_button_enabled'):
		spin_root.call('_set_spin_button_enabled', spin_btn_state)
	if spin_root != null and spin_root.has_method('_apply_spin_button_state'):
		spin_root.call_deferred('_apply_spin_button_state')
	_notify_spin_lock_state()

func _get_requirement_for_round(round_num: int) -> int:
	if round_num <= 0:
		return 0
	if ante_schedule.size() >= round_num:
		var idx: int = round_num - 1
		return max(0, int(ante_schedule[idx]))
	var last: int = 0
	if ante_schedule.size() > 0:
		last = int(ante_schedule[ante_schedule.size() - 1])
	var extra_rounds: int = round_num - ante_schedule.size()
	var inc: int = max(0, ante_increment_after_schedule)
	var req: int = last + (extra_rounds * inc)
	return max(0, req)

# ---------- Totals / Labels ----------
func _gold_bbcode() -> String:
	return "[color=gold]G[/color]"

func _value_label_number_segment(total: int) -> String:
	return "[font_size=%d][outline_size=%d]%s[/outline_size][/font_size]" % [VALUE_LABEL_FONT_SIZE, VALUE_LABEL_OUTLINE_SIZE, str(total)]

func _value_label_gold_segment() -> String:
	return "[font_size=%d][color=gold][outline_size=%d]G[/outline_size][/color][/font_size]" % [VALUE_LABEL_FONT_SIZE, VALUE_LABEL_OUTLINE_SIZE]

func _format_value_label_bbcode(total: int) -> String:
	return _value_label_number_segment(total) + _value_label_gold_segment()

func _set_value_label_gold(total: int) -> void:
	var lbl := _resolve_value_label()
	if lbl == null:
		return
	if lbl is RichTextLabel:
		var rtl := lbl as RichTextLabel
		rtl.bbcode_enabled = true
		rtl.set_deferred("bbcode_text", _format_value_label_bbcode(total))
	else:
		var plain := "%dG" % [total]
		_set_node_text(lbl, plain)

func _update_totals_label(total: int, force: bool = false) -> void:
	if _value_label_defer_depth > 0 and not force:
		return
	var lbl := _resolve_value_label()
	if lbl == null:
		return
	if not animate_bank:
		_set_value_label_gold(total)
		_shown_total = total
		return
	if is_instance_valid(_bank_tween):
		_bank_tween.kill()
	_bank_tween = get_tree().create_tween()
	var dur: float = 0.0
	if bank_anim_duration_sec > 0.0:
		dur = bank_anim_duration_sec
	_bank_tween.tween_method(
		Callable(self, "_set_bank_display"),
		float(_shown_total),
		float(total),
		dur
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bank_tween.finished.connect(func(): _shown_total = total)

func _set_bank_display(v: float) -> void:
	_shown_total = int(round(v))
	_set_value_label_gold(_shown_total)

func _update_round_and_deadline_labels() -> void:
	var target := _owner_node()
	if target == null:
		return
	var spr: int = max(spins_per_round, 1)
	var current_round: int = int(floor(float(spin_index) / float(spr))) + 1
	var requirement: int = _get_requirement_for_round(current_round)

	var round_lbl := _resolve_ui_node(target, "%roundLabel", "roundLabel")
	if round_lbl != null:
		var rt: String = ("Round %d" % current_round).to_upper()
		_set_node_text(round_lbl, rt)

	var deadline_lbl := _resolve_ui_node(target, "%deadlineLabel", "deadlineLabel")
	if deadline_lbl != null:
		var dt: String = "%d%s DUE NEXT ROUND" % [requirement, _gold_bbcode()]
		if deadline_lbl is RichTextLabel:
			(deadline_lbl as RichTextLabel).set_deferred("bbcode_text", dt)
		else:
			_set_node_text(deadline_lbl, dt)

func _update_spin_counters(force_zero: bool = false) -> void:
	var target := _owner_node()
	if target == null:
		return
	var grid := _resolve_ui_node(target, "%spinCounterGrid", "spinCounterGrid")
	if grid == null:
		return
	var spr: int = max(spins_per_round, 1)
	# Show how many spins have been taken IN the current round.
	# Default: 1..spr (shows spr at boundary).
	# When force_zero=true (post-loot/new round), display 0 until the next spin begins.
	var spins_into_round: int = 0
	if not force_zero:
		if spin_index > 0:
			spins_into_round = ((spin_index - 1) % spr) + 1
	var children: Array = (grid as Node).get_children()
	var child_count: int = children.size()
	var active_slots: int = min(spr, child_count)
	for i in range(child_count):
		var ci: Node = children[i]
		if ci is CanvasItem:
			if i < active_slots and i < spins_into_round:
				(ci as CanvasItem).modulate = Color(0, 0, 0, 1)
			else:
				(ci as CanvasItem).modulate = Color(1, 1, 1, 1)

# ---------- Round Pay Overlay ----------
func _build_round_pay_overlay_if_needed() -> void:
	if _round_pay_layer != null and is_instance_valid(_round_pay_layer):
		return
	_round_pay_layer = CanvasLayer.new()
	_round_pay_layer.layer = 90
	var root := Control.new()
	root.name = "RoundPayOverlay"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_round_pay_layer.add_child(root)
	_round_pay_block = root
	var dim := ColorRect.new()
	dim.color = overlay_bg
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 24)
	center.add_child(vb)
	_round_pay_round_label = Label.new()
	_round_pay_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_pay_round_label.add_theme_font_size_override("font_size", 36)
	vb.add_child(_round_pay_round_label)
	_round_pay_status_label = Label.new()
	_round_pay_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_pay_status_label.add_theme_font_size_override("font_size", 24)
	vb.add_child(_round_pay_status_label)
	var values := HBoxContainer.new()
	values.alignment = BoxContainer.ALIGNMENT_CENTER
	values.add_theme_constant_override("separation", 48)
	vb.add_child(values)
	var player_box := VBoxContainer.new()
	player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var player_title := Label.new()
	player_title.text = "YOUR GOLD"
	player_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_title.add_theme_font_size_override("font_size", 20)
	player_box.add_child(player_title)
	_round_pay_player_value_label = RichTextLabel.new()
	_round_pay_player_value_label.bbcode_enabled = true
	_round_pay_player_value_label.scroll_active = false
	_round_pay_player_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_pay_player_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_pay_player_value_label.add_theme_font_size_override("normal_font_size", 48)
	_round_pay_player_value_label.fit_content = true
	player_box.add_child(_round_pay_player_value_label)
	values.add_child(player_box)
	var req_box := VBoxContainer.new()
	req_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var req_title := Label.new()
	req_title.text = "REQUIRED"
	req_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	req_title.add_theme_font_size_override("font_size", 20)
	req_box.add_child(req_title)
	_round_pay_required_value_label = RichTextLabel.new()
	_round_pay_required_value_label.bbcode_enabled = true
	_round_pay_required_value_label.scroll_active = false
	_round_pay_required_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_pay_required_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_pay_required_value_label.add_theme_font_size_override("normal_font_size", 48)
	_round_pay_required_value_label.fit_content = true
	req_box.add_child(_round_pay_required_value_label)
	values.add_child(req_box)
	var attach_to := get_tree().current_scene
	if attach_to == null:
		add_child(_round_pay_layer)
	else:
		attach_to.add_child(_round_pay_layer)
	_round_pay_layer.visible = false

func _hide_round_pay_overlay() -> void:
	if _round_pay_layer != null and is_instance_valid(_round_pay_layer):
		_round_pay_layer.visible = false

func _update_round_pay_labels(player_value: int, requirement_value: int) -> void:
	if _round_pay_player_value_label != null and is_instance_valid(_round_pay_player_value_label):
		_round_pay_player_value_label.bbcode_text = "%d%s" % [player_value, _gold_bbcode()]
	if _round_pay_required_value_label != null and is_instance_valid(_round_pay_required_value_label):
		_round_pay_required_value_label.bbcode_text = "%d%s" % [requirement_value, _gold_bbcode()]

func _shake_canvas_item(ci: CanvasItem) -> void:
	if ci == null or not is_instance_valid(ci):
		return
	var orig_scale: Vector2 = ci.scale
	if orig_scale == Vector2.ZERO:
		orig_scale = Vector2.ONE
	if ci is Control:
		var ctrl := ci as Control
		if ctrl.pivot_offset == Vector2.ZERO:
			ctrl.pivot_offset = ctrl.size * 0.5
	var tween := get_tree().create_tween()
	tween.tween_property(ci, "scale", orig_scale * 1.12, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(ci, "scale", orig_scale, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _play_round_pay_animation(round_num: int, start_coins: int, requirement: int, can_pay: bool, apply_deduction: bool) -> int:
	_build_round_pay_overlay_if_needed()
	if _round_pay_layer != null and is_instance_valid(_round_pay_layer):
		_round_pay_layer.visible = true
	if _round_pay_round_label != null and is_instance_valid(_round_pay_round_label):
		var title_txt := "ROUND %d" % max(round_num, 1)
		_set_node_text(_round_pay_round_label, title_txt)
	if _round_pay_status_label != null and is_instance_valid(_round_pay_status_label):
		var status_txt := "%dG DUE" % requirement
		_set_node_text(_round_pay_status_label, status_txt)
	_update_round_pay_labels(start_coins, requirement)
	await get_tree().process_frame
	var coins_left: int = start_coins
	var requirement_left: int = requirement
	var rate_per_sec: float = ROUND_PAY_BASE_RATE
	var carry: float = 0.0
	var prev_time_usec: int = Time.get_ticks_usec()
	while coins_left > 0 and requirement_left > 0:
		await get_tree().process_frame
		var now_usec: int = Time.get_ticks_usec()
		var dt: float = float(now_usec - prev_time_usec) / 1_000_000.0
		if dt < ROUND_PAY_MIN_FRAME:
			dt = ROUND_PAY_MIN_FRAME
		prev_time_usec = now_usec
		rate_per_sec = min(ROUND_PAY_MAX_RATE, rate_per_sec * pow(ROUND_PAY_ACCEL_PER_SEC, dt))
		carry += rate_per_sec * dt
		var available: int = int(floor(carry))
		if available <= 0:
			continue
		var to_remove: int = min(available, coins_left)
		to_remove = min(to_remove, requirement_left)
		if to_remove <= 0:
			continue
		carry -= float(to_remove)
		coins_left -= to_remove
		requirement_left -= to_remove
		_update_round_pay_labels(coins_left, requirement_left)
	_update_round_pay_labels(coins_left, requirement_left)
	var status_txt_final: String = ""
	var winning_item: CanvasItem = null
	if requirement_left <= 0 and can_pay:
		status_txt_final = "ROUND COMPLETE"
		winning_item = _round_pay_player_value_label
	else:
		var shortfall: int = max(requirement_left, 0)
		status_txt_final = "...%dG" % shortfall
		winning_item = _round_pay_required_value_label
	if _round_pay_status_label != null and is_instance_valid(_round_pay_status_label):
		_set_node_text(_round_pay_status_label, status_txt_final)
	if winning_item != null:
		_shake_canvas_item(winning_item)
	await _pause(2)
	_hide_round_pay_overlay()
	if not apply_deduction:
		return start_coins
	return coins_left

# ---------- Game Over Overlay ----------
func _trigger_game_over(round_num: int, requirement: int) -> void:
	_build_game_over_overlay_if_needed()
	# Ensure any pending loot overlay is hidden when game over occurs
	_hide_loot_overlay()
	_show_game_over(round_num, requirement, total_coins)
	_game_over_active = true
	# Invalidate any pending loot UI tasks
	_loot_gen += 1
	emit_signal("game_over_shown", round_num, requirement, total_coins)

func _build_game_over_overlay_if_needed() -> void:
	if _go_layer != null and is_instance_valid(_go_layer):
		return
	_go_layer = CanvasLayer.new()
	_go_layer.layer = 100
	var root := Control.new()
	root.name = "GameOverOverlay"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_go_layer.add_child(root)
	_go_block = root

	var dim := ColorRect.new()
	dim.color = overlay_bg
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 16)
	center.add_child(vb)

	var title := Label.new()
	title.text = game_over_text
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", game_over_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var info := Label.new()
	info.name = "InfoLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(info)

	_go_btn = Button.new()
	_go_btn.text = last_spin_button_text
	_go_btn.custom_minimum_size = Vector2(180, 40)
	vb.add_child(_go_btn)
	_go_btn.pressed.connect(_on_last_spin_pressed)

	var attach_to := get_tree().current_scene
	if attach_to == null:
		add_child(_go_layer)
	else:
		attach_to.add_child(_go_layer)
	_go_layer.visible = false

func _show_game_over(round_num: int, requirement: int, coins: int) -> void:
	if _go_layer == null or not is_instance_valid(_go_layer):
		return
	var info := _go_block.get_node_or_null("CenterContainer/VBoxContainer/InfoLabel")
	if info is Label:
		(info as Label).text = "Round %d required %d coins.\nYou had %d." % [round_num, requirement, coins]
	_go_layer.visible = true

func _hide_game_over() -> void:
	if _go_layer != null and is_instance_valid(_go_layer):
		_go_layer.visible = false
	_game_over_active = false

func _on_last_spin_pressed() -> void:
	reset_run()
	_hide_game_over()

# ---------- Token calc helpers ----------
func _mk_contrib(token, kind: String, base_val: int, offset: int) -> Dictionary:
	var rarity_val = null
	if token != null:
		_ensure_token_uid(token)
	if token != null and token.has_method("get"):
		var rv = token.get("rarity")
		if rv != null:
			rarity_val = rv

	var desc: String = _get_token_description(token, kind)

	return {
		"token": token,
		"kind": kind,
		"offset": offset,
		"base": max(base_val, 0),
		"delta": 0,
		"mult": 1.0,
		"steps": [],
		"meta": {
			"final": 0,
			"rarity": rarity_val,
			"description": desc
		}
	}

# Snapshot pre-effect contrib data for hover previews.
func _snapshot_baseline_contribs(contribs: Array) -> Array:
	var snapshot: Array = []
	for entry in contribs:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = entry
		var snap := {}
		snap["offset"] = int(c.get("offset", 0))
		snap["kind"] = String(c.get("kind", ""))
		snap["base_value"] = int(c.get("base", 0))
		var tok = c.get("token")
		snap["token"] = tok
		if tok != null and (tok as Object).has_method("get"):
			var name_val = tok.get("name")
			if typeof(name_val) == TYPE_STRING:
				snap["token_name"] = String(name_val)
			var icon_val = tok.get("icon")
			if icon_val != null:
				snap["icon"] = icon_val
		if tok is Resource and (tok as Resource).resource_path != "":
			snap["resource_path"] = (tok as Resource).resource_path
		snapshot.append(snap)
	return snapshot


func _apply_step(c: Dictionary, step: Dictionary) -> void:
	var before: Dictionary = {
		"base": int(c.base),
		"delta": int(c.delta),
		"mult": float(c.mult),
		"val": _compute_value(c)
	}
	var kind := String(step.get("kind", ""))
	var prev_val := int(before.get("val", 0))
	var final_applied := 0
	match kind:
		"add":
			c.delta = int(c.delta) + int(step.get("amount", 0))
		"mult":
			var f: float = float(step.get("factor", 1.0))
			if f < 0.0:
				f = 0.0
			c.mult = float(c.mult) * f
		"final_add":
			var amount := int(step.get("amount", 0))
			var min_final := int(step.get("min_value", -1))
			var target_val := prev_val + amount
			if min_final >= 0 and target_val < min_final:
				target_val = min_final
			if target_val < 0:
				target_val = 0
			var achieved := _set_contrib_final_value(c, target_val)
			final_applied = achieved - prev_val
		_:
			pass
	# Clamp base permanent value to at least 1
	if int(c.base) + int(c.delta) < 1:
		c.delta = 1 - int(c.base)
	if float(c.mult) < 0.0:
		c.mult = 0.0
	var after: Dictionary = {
		"base": int(c.base),
		"delta": int(c.delta),
		"mult": float(c.mult),
		"val": _compute_value(c)
	}
	if kind == "final_add":
		final_applied = int(after.get("val", _compute_value(c))) - prev_val
	var mult_applied: float = 0.0
	if float(before.mult) != 0.0:
		mult_applied = float(after.mult) / float(before.mult)
	else:
		mult_applied = float(after.mult)
	var logged: Dictionary = {
		"source": step.get("source", "unknown"),
		"kind": kind,
		"desc": step.get("desc", ""),
		"before": before,
		"after": after,
		"add_applied": int(after.delta) - int(before.delta),
		"mult_applied": mult_applied,
		"ability_ref": step.get("_ability_ref", null)
	}
	if kind == "final_add":
		logged["final_applied"] = final_applied
	(c.steps as Array).append(logged)
	_update_token_temp_meta_from_contrib(c.get("token"), c, _is_step_temporary(step))

func _compute_value(c: Dictionary) -> int:
	var base: int = int(c.base)
	var delta: int = int(c.delta)
	var mult: float = float(c.mult)
	var sum: int = base + delta
	if sum < 0:
		sum = 0
	var val: int = int(floor(sum * max(mult, 0.0)))
	return max(val, 0)

func _finalize_contrib(c: Dictionary) -> int:
	var v: int = _compute_value(c)
	(c.meta as Dictionary)["final"] = v
	return v

func _collect_token_description_steps(ctx: Dictionary, contrib: Dictionary) -> Array:
	var token = contrib.token
	var steps: Array = []
	if token == null:
		return steps
	if token.has_method("build_coin_steps"):
		steps = token.build_coin_steps(ctx, contrib)
	elif token.has_method("get"):
		var eff = token.get("effect")
		if eff is ArtifactData and eff.applies(ctx, contrib):
			steps = eff.build_steps(ctx, contrib)
	elif token.has_method("apply_coin_effect"):
		steps = token.apply_coin_effect(ctx, contrib)
	var normalized: Array = []
	for s in steps:
		var step: Dictionary = {
			"kind": s.get("kind", ""),
			"amount": int(s.get("amount", 0)),
			"factor": float(s.get("factor", 1.0)),
			"desc": String(s.get("desc", "")),
			"source": s.get("source", "token")
		}
		normalized.append(step)
	return normalized

# Collect Active During Spin ability steps (Self; Winner Only honored)
# Collect Active During Spin ability steps split into immediate vs deferred (winner_only → deferred on winner)
func _collect_ability_spin_steps(ctx: Dictionary, contrib: Dictionary, winner) -> Dictionary:
	var token = contrib.token
	var parts := {
		"immediate": [],
		"deferred": []
	}
	if token == null or not token.has_method("get"):
		return parts
	var abilities = token.get("abilities")
	if not (abilities is Array):
		return parts

	for ab in abilities:
		if ab == null:
			continue
		if debug_spin:
			print("[Ability] Inspect ", _obj_name(ab), " for offset ", contrib.offset)

		# Must be Active During Spin
		if not _ability_is_active_during_spin(ab):
			if debug_spin: print("  [Ability] Skip: trigger not Active During Spin")
			continue

		var is_winner_only := _ability_winner_only(ab)
		var is_winner_slot := int(contrib.offset) == 0

		# Winner-only abilities never act on passive slots
		if is_winner_only and not is_winner_slot:
			if debug_spin: print("  [Ability] Skip: winner-only but not winner slot")
			continue

		# Preferred: author-provided per-token steps
		if (ab as Object).has_method("build_steps"):
			var arr = ab.build_steps(ctx, contrib, token)
			if arr is Array and not arr.is_empty():
				if is_winner_only and is_winner_slot:
					for s in arr:
						var step_norm := _normalize_step(s)
						step_norm["_ability_ref"] = ab
						step_norm["_stage"] = "ability_deferred"
						(parts["deferred"] as Array).append(step_norm)
					if debug_spin: print("  [Ability] +steps (deferred winner_only): ", arr.size())
				else:
					for s in arr:
						var step_norm := _normalize_step(s)
						step_norm["_ability_ref"] = ab
						step_norm["_stage"] = "ability"
						(parts["immediate"] as Array).append(step_norm)
					if debug_spin: print("  [Ability] +steps (immediate): ", arr.size())
			continue

		# Legacy autostep (opt-in)
		var auto := false
		if (ab as Object).has_method("wants_auto_self_step"):
			auto = bool(ab.call("wants_auto_self_step"))
		else:
			var flag = ab.get("auto_self_step")
			if flag != null: auto = bool(flag)
		if not auto:
			if debug_spin: print("  [Ability] Skip: no build_steps and autostep opt-in is false")
			continue

		# Self-only autostep
		var tk: String = _ability_target_kind(ab)
		if tk != "" and tk.to_lower() != "self":
			if debug_spin: print("  [Ability] Skip: autostep supports self only (got ", tk, ")")
			continue

		var fac: float = max(0.0, _ability_factor(ab))
		var amt: int = int(max(0.0, _ability_amount(ab)))
		var kind_s := ""
		if fac > 0.0 and abs(fac - 1.0) > 0.0001: kind_s = "mult"
		elif amt != 0: kind_s = "add"
		if kind_s == "":
			if debug_spin: print("  [Ability] Skip: neither valid factor nor amount")
			continue

		var src := "ability:" + _ability_id_or_class(ab)
		var desc := _ability_desc(ab, fac, amt, token)
		var step := {
			"kind": kind_s,
			"amount": amt,
			"factor": fac if kind_s == "mult" else 1.0,
			"desc": desc,
			"source": src
		}
		step["_ability_ref"] = ab
		if is_winner_only and is_winner_slot:
			step["_stage"] = "ability_deferred"
			(parts["deferred"] as Array).append(step)
			if debug_spin: print("  [Ability] +autostep (deferred winner_only): ", step)
		else:
			step["_stage"] = "ability"
			(parts["immediate"] as Array).append(step)
			if debug_spin: print("  [Ability] +autostep (immediate): ", step)

	return parts
# ---------- Winner active summary ----------
func _on_winner_description_shown(winner, _text_ignored: String) -> void:
	var lbl := _resolve_active_effect_label()
	if lbl == null:
		return

	var title := ""
	if winner != null and winner.has_method("get"):
		var n = winner.get("name")
		if typeof(n) == TYPE_STRING:
			title = String(n)
	if title.strip_edges() == "":
		title = str(winner)

	# Only show the active token name; omit description

	var title_hex := "#f62c25"
	if lbl is RichTextLabel:
		var rtl := lbl as RichTextLabel
		rtl.bbcode_enabled = true
		if rtl.get_meta("__base_font_size", null) == null:
			var base_size := rtl.get_theme_font_size("normal_font_size", "RichTextLabel")
			if base_size <= 0:
				base_size = 24
			rtl.set_meta("__base_font_size", base_size)
		var text := "[color=%s]%s[/color]" % [title_hex, title.to_upper()]
		rtl.bbcode_text = text
		rtl.set_meta("__font_reduced", false)
		call_deferred("_adjust_active_effect_label_font", rtl)
	else:
		_set_node_text(lbl, "%s" % [title.to_upper()])

func _resolve_active_effect_label() -> Node:
	if _active_effect_label != null and is_instance_valid(_active_effect_label):
		return _active_effect_label
	_active_effect_label = _resolve_ui_node(_owner_node(), "%activeEffect", "activeEffect")
	return _active_effect_label

func _adjust_active_effect_label_font(rtl: RichTextLabel) -> void:
	if rtl == null or !is_instance_valid(rtl):
		return
	var base_size := int(rtl.get_meta("__base_font_size", 24))
	var was_reduced := bool(rtl.get_meta("__font_reduced", false))
	var line_count := 1
	if rtl.has_method("get_visible_line_count"):
		line_count = int(rtl.call("get_visible_line_count"))
	elif rtl.has_method("get_line_count"):
		line_count = int(rtl.call("get_line_count"))
	var threshold := int(rtl.get_meta("__line_threshold", 1))
	var needs_reduce := line_count > threshold or rtl.text.length() > 80
	if needs_reduce and !was_reduced:
		var target_size: int = max(12, base_size - 6)
		rtl.add_theme_font_size_override("normal_font_size", target_size)
		rtl.set_meta("__font_reduced", true)
	elif !needs_reduce and was_reduced:
		rtl.remove_theme_font_size_override("normal_font_size")
		rtl.set_meta("__font_reduced", false)

# ---------- Loot overlay + picking ----------
func _trigger_loot_choice(round_num: int, forced: bool = false, ctx: Dictionary = {}) -> bool:
	# Do not offer loot if a Game Over is active
	if _game_over_active:
		return false
	if _artifact_selection_active or _artifact_selection_queued:
		var ctx_copy: Dictionary = {}
		if ctx != null and ctx is Dictionary:
			ctx_copy = (ctx as Dictionary).duplicate(true)
		_pending_loot_request = {
			"round": round_num,
			"forced": forced,
			"ctx": ctx_copy
		}
		return false
	_loot_selection_forced = forced
	if forced:
		_loot_selection_pending = true
		_notify_spin_lock_state(ctx)
	# Passive: Treasure Hoard spawns a random Chest each round
	_apply_treasure_hoard_spawn()
	var bonus: int = int(_loot_options_bonus)
	if bonus < 0:
		bonus = 0
	var total_opts: int = max(1, loot_options_count + bonus)
	var options: Array = _get_loot_options(total_opts, round_num)
	# consume the bonus
	_loot_options_bonus = 0
	if options.is_empty():
		var token: Resource = _load_empty_token()
		_emit_loot_selected(round_num, token)
		_loot_selection_pending = false
		_loot_selection_forced = false
		_update_loot_skip_state()
		_notify_spin_lock_state(ctx)
		return false
	_loot_selection_pending = true
	_update_loot_skip_state()
	_notify_spin_lock_state(ctx)
	_pending_loot_request.clear()
	_build_loot_overlay_if_needed()
	var gen := _loot_gen
	_show_loot_overlay(round_num, options, gen)
	emit_signal("loot_choice_needed", round_num)
	return true

func _build_loot_overlay_if_needed() -> void:
	if _loot_layer != null and is_instance_valid(_loot_layer):
		return

	var attach_to := get_tree().current_scene
	if attach_to == null:
		attach_to = get_tree().root

	_loot_layer = CanvasLayer.new()
	_loot_layer.layer = 90
	_loot_layer.offset = Vector2.ZERO
	_loot_layer.rotation = 0.0
	_loot_layer.scale = Vector2.ONE
	attach_to.add_child(_loot_layer)

	var root := Control.new()
	root.name = "LootOverlay"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_anchor_full_rect(root)

	_loot_layer.add_child(root)
	_loot_block = root

	var dim := ColorRect.new()
	dim.color = overlay_bg
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	center.add_child(vb)

	var title := Label.new()
	title.text = loot_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vb.add_child(title)
	_loot_title_label = title
	_refresh_loot_title()

	_loot_options_hbox = HBoxContainer.new()
	_loot_options_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_loot_options_hbox.add_theme_constant_override("separation", int(16 * loot_tile_scale))
	vb.add_child(_loot_options_hbox)

	_loot_skip_btn = Button.new()
	_loot_skip_btn.text = skip_button_text
	_loot_skip_btn.custom_minimum_size = Vector2(HORIZONTAL_ALIGNMENT_FILL, 100)
	vb.add_child(_loot_skip_btn)

	_loot_layer.visible = false


func _show_loot_overlay(round_num: int, options: Array, expected_gen: int = -1) -> void:
	await get_tree().process_frame
	if loot_post_spin_delay > 0.0:
		await get_tree().create_timer(loot_post_spin_delay).timeout

	# If a Game Over occurred or the generation changed while waiting, abort showing loot
	if _game_over_active:
		return
	if expected_gen >= 0 and expected_gen != _loot_gen:
		return

	if _loot_layer != null and is_instance_valid(_loot_layer):
		_loot_layer.offset = Vector2.ZERO
		_loot_layer.rotation = 0.0
		_loot_layer.scale = Vector2.ONE
	if _loot_block != null and is_instance_valid(_loot_block):
		_anchor_full_rect(_loot_block)

	_refresh_loot_title()
	_loot_last_round = round_num

	print("[Loot] Offered options for round ", round_num, ":")
	for i in range(options.size()):
		var t = options[i]
		if t != null and t.has_method("get"):
			var n = str(t.get("name"))
			var r = t.get("rarity")
			var v = t.get("value")
			var w = t.get("weight")
			print("  - ", n, " | rarity=", r, " | value=", v, " | weight=", w)

	_clear_children(_loot_options_hbox)

	var SLOT_BASE := 96
	var TILE_BASE := 96
	var ICON_BASE := 64
	var slot_px := int(round(SLOT_BASE * loot_tile_scale))
	var tile_px := int(round(TILE_BASE * loot_tile_scale))
	var icon_px := int(round(ICON_BASE * loot_tile_scale))

	for token in options:
		# Ensure loot shows the current per-run adjusted value
		if not _artifact_selection_active:
			_init_token_base_value(token)
		var frame := PanelContainer.new()
		frame.name = "ItemFrame"
		frame.custom_minimum_size = Vector2(tile_px, tile_px)
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.0)
		sb.set_border_width_all(4)
		sb.border_color = Color(1, 1, 1, 1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(6)
		frame.add_theme_stylebox_override("panel", sb)
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		var rare_col := Color(1, 1, 1, 1)
		if token != null and token.has_method("get_color"):
			rare_col = token.call("get_color")
		(frame.get_theme_stylebox("panel") as StyleBoxFlat).border_color = rare_col

		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(center)

		var used_scene := false
		var press_target: Button = null

		if token_icon_scene != null and not _artifact_selection_active:
			var inst := token_icon_scene.instantiate()
			if inst is Button:
				press_target = inst as Button
				press_target.set("slot_size", Vector2i(slot_px, slot_px))
				press_target.custom_minimum_size = Vector2(slot_px, slot_px)
				press_target.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				press_target.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				press_target.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				press_target.set("data", token)
				press_target.set_meta("token_data", token)
				press_target.set_meta("artifact_pick", _artifact_selection_active)
				var tip := TooltipSpawner.new()
				tip.name = "TooltipSpawner"
				tip.set_meta("token_data", token)
				press_target.add_child(tip)
				center.add_child(press_target)
				used_scene = true

		if not used_scene:
			var btn := Button.new()
			btn.toggle_mode = false
			btn.focus_mode = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(tile_px, tile_px)
			btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.flat = true
			btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

			var inner := CenterContainer.new()
			inner.set_anchors_preset(Control.PRESET_FULL_RECT)
			inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(inner)

			var icon_tex := TextureRect.new()
			icon_tex.name = "IconTexture"
			icon_tex.custom_minimum_size = Vector2(icon_px, icon_px)
			icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tex: Texture2D = _try_get_icon_texture(token)
			icon_tex.texture = tex
			inner.add_child(icon_tex)

			btn.set_meta("token_data", token)
			btn.set_meta("artifact_pick", _artifact_selection_active)
			var tip2 := TooltipSpawner.new()
			tip2.name = "TooltipSpawner"
			tip2.set_meta("token_data", token)
			btn.add_child(tip2)

			center.add_child(btn)
			press_target = btn

		if press_target != null:
			if press_target.is_connected("pressed", Callable(self, "_on_loot_pressed_node")):
				press_target.pressed.disconnect(Callable(self, "_on_loot_pressed_node"))
			press_target.pressed.connect(_on_loot_pressed_node.bind(press_target))

		_loot_options_hbox.add_child(frame)

	if _loot_skip_btn != null:
		if _loot_skip_btn.is_connected("pressed", Callable(self, "_on_loot_skip_pressed")):
			_loot_skip_btn.pressed.disconnect(Callable(self, "_on_loot_skip_pressed"))
		_loot_skip_btn.pressed.connect(_on_loot_skip_pressed.bind(round_num))
		_update_loot_skip_state()

	var center_cont := _loot_block.get_node_or_null("CenterContainer") as Container
	var column_cont := _loot_block.get_node_or_null("CenterContainer/VBoxContainer") as Container

	if _loot_options_hbox != null and is_instance_valid(_loot_options_hbox):
		_loot_options_hbox.queue_sort()
	if column_cont != null and is_instance_valid(column_cont):
		column_cont.queue_sort()
	if center_cont != null and is_instance_valid(center_cont):
		center_cont.queue_sort()

	await get_tree().process_frame

	if _loot_options_hbox != null and is_instance_valid(_loot_options_hbox):
		_loot_options_hbox.queue_sort()
	if column_cont != null and is_instance_valid(column_cont):
		column_cont.queue_sort()
	if center_cont != null and is_instance_valid(center_cont):
		center_cont.queue_sort()

	await get_tree().process_frame
	# Final guard before making visible
	if _game_over_active:
		return
	if expected_gen >= 0 and expected_gen != _loot_gen:
		return
	_loot_layer.visible = true

func _hide_loot_overlay() -> void:
	if _loot_layer != null and is_instance_valid(_loot_layer):
		_loot_layer.visible = false
	_loot_selection_pending = false
	_loot_selection_forced = false
	_artifact_selection_active = false
	_artifact_current_options.clear()
	_refresh_loot_title()
	_update_loot_skip_state()
	_notify_spin_lock_state()

func _update_loot_skip_state() -> void:
	if _loot_skip_btn != null and is_instance_valid(_loot_skip_btn):
		_loot_skip_btn.visible = not _loot_selection_forced
		_loot_skip_btn.disabled = _loot_selection_forced
func _on_loot_pressed_node(node: Button) -> void:
	var data = null
	if node.has_meta("token_data"):
		data = node.get_meta("token_data")
	if node.has_meta("artifact_pick") and bool(node.get_meta("artifact_pick")):
		_handle_artifact_pick(data)
		return
	var token: Resource = data as Resource
	_emit_loot_selected(_loot_last_round, token)

func _on_loot_skip_pressed(round_num: int) -> void:
	if _loot_selection_forced:
		return
	var token: Resource = _load_empty_token()
	_emit_loot_selected(round_num, token)

func _emit_loot_selected(round_num: int, token: Resource) -> void:
	_loot_selection_pending = false
	_loot_selection_forced = false
	_hide_loot_overlay()

	var tok: Resource = token
	if tok != null and tok is Resource:
		tok = (tok as Resource).duplicate(true)
		_init_token_base_value(tok)

	var replaced: bool = false
	var prop_str: String = String(inventory_property).strip_edges()
	var owner_str: String = String(inventory_owner_path)

	if prop_str != "" and owner_str != "":
		var arr := _get_inventory_array()
		if arr.size() > 0:
			var idx := _find_empty_index(arr)
			if idx >= 0:
				arr[idx] = tok
				# Handle duplicate-on-add abilities (e.g., Copper Coin total_copies=2)
				var copies: int = _copies_to_add_for_token(tok)
				var extra: int = copies - 1
				if extra < 0:
					extra = 0
				for j in range(extra):
					var jidx := _find_empty_index(arr)
					if jidx < 0:
						break
					var dup: Resource = (tok as Resource).duplicate(true)
					_init_token_base_value(dup)
					arr[jidx] = dup
				# Commit once after all replacements to minimize churn
				_set_inventory_array(arr)
				# Emit signal for the initial replacement; UI can resync if needed
				emit_signal("loot_choice_replaced", round_num, tok, idx)
				replaced = true

	if not replaced:
		emit_signal("loot_choice_selected", round_num, tok)

	# New round begins after a token is added/replaced. Refresh counters to 0.
	_update_round_and_deadline_labels()
	_update_spin_counters()
	_try_start_artifact_selection()

func _load_empty_token() -> Resource:
	var res: Resource = null
	var path: String = empty_token_path.strip_edges()
	if path != "":
		var r := ResourceLoader.load(path)
		if r is Resource:
			res = r as Resource
	return res

# Determine how many copies to add for a token on acquire (default 1)
func _copies_to_add_for_token(token: Resource) -> int:
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

# ---------- Loot pool / picking ----------
func _get_loot_options(count: int, round_num: int) -> Array:
	var pool: Array = _scan_token_assets(loot_scan_root)
	print("[Loot] Scanned pool from ", loot_scan_root, " (", pool.size(), " items):")
	for t in pool:
		if t != null and t.has_method("get"):
			print("  * ", String(t.get("name")), " | rarity=", t.get("rarity"), " | value=", t.get("value"), " | weight=", t.get("weight"))
	if pool.is_empty():
		return []
	var sched: LootRaritySchedule = _active_rarity_schedule()
	var options: Array = []
	if sched == null:
		options = _pick_weighted_unique(pool, count, _loot_rng)
	else:
		var base_weights: Dictionary = sched.get_rarity_weights(round_num)
		var adjusted: Dictionary = _apply_rarity_modifiers(base_weights, round_num, _loot_rng)
		options = _pick_with_rarity_schedule(pool, count, _loot_rng, round_num, sched, adjusted)
	if not _next_loot_guarantees.is_empty():
		options = _apply_loot_guarantees(options, pool, _loot_rng)
		_next_loot_guarantees.clear()
	return options

func _apply_loot_guarantees(options: Array, pool: Array, rng: RandomNumberGenerator) -> Array:
	if options.is_empty():
		return options
	var targets: Dictionary = {}
	for k in _next_loot_guarantees.keys():
		var key := String(k).to_lower()
		var cnt := int(max(1, _next_loot_guarantees[k]))
		var prev := int(targets.get(key, 0))
		if cnt > prev:
			targets[key] = cnt
	if targets.is_empty():
		return options
	var current: Dictionary = {}
	for opt in options:
		if opt != null and (opt as Object).has_method("get"):
			var rar := String(opt.get("rarity")).to_lower()
			current[rar] = int(current.get(rar, 0)) + 1
	var pool_by_rarity: Dictionary = {}
	for tok in pool:
		if tok != null and (tok as Object).has_method("get"):
			var rar2 := String(tok.get("rarity")).to_lower()
			if targets.has(rar2):
				var arr: Array = pool_by_rarity.get(rar2, [])
				arr.append(tok)
				pool_by_rarity[rar2] = arr
	for rarity in targets.keys():
		var target_count := int(targets[rarity])
		var have := int(current.get(rarity, 0))
		var missing = max(0, target_count - have)
		if missing <= 0:
			continue
		var candidates: Array = pool_by_rarity.get(rarity, [])
		if candidates.is_empty():
			continue
		while missing > 0 and not candidates.is_empty():
			var picked = candidates[rng.randi_range(0, candidates.size() - 1)]
			var dup = picked
			if picked is Resource:
				dup = (picked as Resource).duplicate(true)
			if dup is Resource:
				_init_token_base_value(dup)
			var replace_idx := _find_loot_replace_slot(options, targets, current, rarity)
			if replace_idx < 0:
				break
			var prev_opt = options[replace_idx]
			if prev_opt != null and (prev_opt as Object).has_method("get"):
				var prev_r := String(prev_opt.get("rarity")).to_lower()
				current[prev_r] = int(current.get(prev_r, 0)) - 1
			options[replace_idx] = dup
			current[rarity] = int(current.get(rarity, 0)) + 1
			missing -= 1
	return options

func _find_loot_replace_slot(options: Array, target_counts: Dictionary, current_counts: Dictionary, desired_rarity: String) -> int:
	for i in range(options.size()):
		var opt = options[i]
		if opt == null or not (opt as Object).has_method("get"):
			return i
		var rar := String(opt.get("rarity")).to_lower()
		var target := int(target_counts.get(rar, 0))
		if int(current_counts.get(rar, 0)) > target:
			return i
	for i in range(options.size()):
		var opt = options[i]
		if opt == null or not (opt as Object).has_method("get"):
			return i
		var rar := String(opt.get("rarity")).to_lower()
		if rar != desired_rarity:
			return i
	return options.size() - 1

func _scan_token_assets(root: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			if name.begins_with("."):
				continue
			out.append_array(_scan_token_assets(root.path_join(name)))
		else:
			if not (name.ends_with(".tres") or name.ends_with(".res")):
				continue
			var path := root.path_join(name)
			if path == empty_token_path:
				continue
			var res := ResourceLoader.load(path)
			if res != null and (res is TokenLootData or (res.has_method("get") and res.has_method("get_color"))):
				out.append(res)
	dir.list_dir_end()
	return out

func _pick_weighted_unique(pool: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	if pool.is_empty() or count <= 0:
		return result
	var candidates: Array = pool.duplicate()
	count = min(count, candidates.size())
	for i in range(count):
		var choice = _weighted_choice(candidates, rng)
		if choice == null:
			break
		result.append(choice)
		candidates.erase(choice)
	return result

# Pick an index from an Array using each item's token.get("weight") (default 1.0).
func _weighted_choice(pool: Array, rng: RandomNumberGenerator) -> Variant:
	var total: float = 0.0
	var weights: Array[float] = []
	weights.resize(pool.size())

	for i in range(pool.size()):
		var t = pool[i]
		var w: float = 1.0
		if t != null and t is Object and (t as Object).has_method("get"):
			var v = t.get("weight")
			if v != null:
				w = max(0.0, float(v))
		if w <= 0.0:
			weights[i] = 0.0
		else:
			weights[i] = w
			total += w

	if total <= 0.0:
		return null

	var r: float = rng.randf() * total
	var acc: float = 0.0
	for i in range(pool.size()):
		acc += weights[i]
		if r <= acc and weights[i] > 0.0:
			return pool[i]

	return pool.back()

# Pick a key from a Dictionary of rarity->weight; used only for rarity selection.
func _weighted_choice_by_map(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys: Array[String] = []
	var vals: Array[float] = []
	for k in weights.keys():
		keys.append(String(k))
		vals.append(max(0.0, float(weights[k])))
	var total: float = 0.0
	for v in vals:
		total += v
	if total <= 0.0:
		return keys[0] if keys.size() > 0 else ""
	var r: float = rng.randf() * total
	var acc: float = 0.0
	for i in range(vals.size()):
		acc += vals[i]
		if r <= acc:
			return keys[i]
	return keys.back()

# ---------- Icon helpers ----------
func _try_get_icon_texture(token) -> Texture2D:
	if token == null or not token.has_method("get"):
		return null

	var direct_keys := ["icon", "Icon", "texture", "Texture"]
	for key in direct_keys:
		var v = token.get(key)
		if v != null and v is Texture2D:
			return v as Texture2D

	var path_keys := ["iconPath", "icon_path", "path"]
	for key in path_keys:
		var s = token.get(key)
		if typeof(s) == TYPE_STRING:
			var p: String = String(s).strip_edges()
			if p != "":
				var r := ResourceLoader.load(p)
				if r is Texture2D:
					return r as Texture2D

	if token.has_method("get_icon"):
		var t = token.call("get_icon")
		if t is Texture2D:
			return t as Texture2D

	return null

# ---------- Inventory helpers (replacement) ----------
func _get_inventory_array() -> Array:
	var owner := get_node_or_null(inventory_owner_path)
	if owner == null:
		owner = _resolve_inventory_owner_node()
	if owner == null or not owner.has_method("get"):
		return []
	var prop := String(inventory_property)
	if prop.strip_edges() == "":
		prop = "items"
	var inv = owner.get(prop)
	if typeof(inv) == TYPE_ARRAY:
		return inv
	# Fallback: many owners (e.g., spinRoot) expose `items` instead of `tokens`.
	if prop != "items":
		var alt = owner.get("items")
		if typeof(alt) == TYPE_ARRAY:
			return alt
	return []

func _set_inventory_array(arr: Array) -> void:
	var owner := get_node_or_null(inventory_owner_path)
	if owner == null:
		owner = _resolve_inventory_owner_node()
	if owner == null:
		return
	var prop := String(inventory_property)
	if prop.strip_edges() == "":
		prop = "items"
	owner.set(prop, arr)

func _find_empty_index(arr: Array) -> int:
	var indices: Array = []
	for i in range(arr.size()):
		if _is_empty_token(arr[i]):
			indices.append(i)
	if indices.is_empty():
		return -1
	if empty_replace_strategy == "last":
		return int(indices.back())
	if empty_replace_strategy == "random":
		var rng := _mk_rng()
		var pick := int(rng.randi_range(0, indices.size() - 1))
		return int(indices[pick])
	return int(indices[0])

func _is_empty_token(t) -> bool:
	if t == null:
		return true
	if empty_token_path.strip_edges() != "" and t is Resource:
		var rp := (t as Resource).resource_path
		if rp != "" and rp == empty_token_path:
			return true
	if t is Object and (t as Object).has_method("get"):
		var is_empty = t.get("isEmpty")
		if is_empty != null and bool(is_empty):
			return true
		var nm = t.get("name")
		if typeof(nm) == TYPE_STRING:
			var s := String(nm).strip_edges().to_lower()
			if s == "empty" or s == "empty token":
				return true
	return false

func _token_path_is_empty(token_path: String) -> bool:

	var normalized := String(token_path).strip_edges()

	if normalized == "":

		return false

	var reference := String(empty_token_path).strip_edges()

	if reference == "":

		return false

	return normalized == reference

# ---------- Layout helpers ----------
func _anchor_full_rect(ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 1.0
	ctrl.anchor_bottom = 1.0
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
	ctrl.position = Vector2.ZERO

# ---------- misc ----------
func _clear_children(n: Node) -> void:
	if n == null:
		return
	for c in n.get_children():
		c.queue_free()

func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if _loot_block != null and is_instance_valid(_loot_block):
			_anchor_full_rect(_loot_block)
			var center_cont := _loot_block.get_node_or_null("CenterContainer") as Container
			var column_cont := _loot_block.get_node_or_null("CenterContainer/VBoxContainer") as Container
			if _loot_options_hbox != null and is_instance_valid(_loot_options_hbox):
				_loot_options_hbox.queue_sort()
			if column_cont != null and is_instance_valid(column_cont):
				column_cont.queue_sort()
			if center_cont != null and is_instance_valid(center_cont):
				center_cont.queue_sort()

# ---------- tiny token utils ----------
func _token_name(t) -> String:
	if t != null and t.has_method("get"):
		var n = t.get("name")
		if typeof(n) == TYPE_STRING:
			return String(n)
	return ""

func _token_has_tag(t, tag: String) -> bool:
	if t == null or not t.has_method("get"):
		return false
	var tag_norm := String(tag).strip_edges().to_lower()
	if tag_norm == "":
		return false
	var tags = t.get("tags")
	if tags is Array:
		for s in tags:
			if typeof(s) == TYPE_STRING and String(s).to_lower() == tag_norm:
				return true
	elif typeof(tags) == TYPE_PACKED_STRING_ARRAY:
		var psa: PackedStringArray = tags
		for s in psa:
			if String(s).to_lower() == tag_norm:
				return true
	return false

func _token_is_coin(t) -> bool:
	if t == null:
		return false
	if _token_has_tag(t, "coin"):
		return true
	return _token_name(t).to_lower() == "coin"

func _token_key(t) -> String:
	if t is Resource and (t as Resource).resource_path != "":
		return String((t as Resource).resource_path)
	var nm := _token_name(t).strip_edges().to_lower()
	if nm != "":
		return nm
	return str(t)

func ensure_token_uid(token: Variant) -> int:
	return _ensure_token_uid(token)

func _ensure_token_uid(token: Variant) -> int:
	if token == null:
		return 0
	if not (token as Object).has_method("set_meta"):
		return 0
	var existing_uid := 0
	var owner_id := 0
	if (token as Object).has_method("has_meta"):
		if token.has_meta("__highlight_uid"):
			existing_uid = int(token.get_meta("__highlight_uid"))
		if token.has_meta("__highlight_uid_owner"):
			owner_id = int(token.get_meta("__highlight_uid_owner"))
	var inst_id := 0
	if (token as Object).has_method("get_instance_id"):
		inst_id = int(token.get_instance_id())
	if existing_uid != 0 and owner_id == inst_id and existing_uid != 0:
		return existing_uid
	var uid := existing_uid
	uid = _next_highlight_uid
	_next_highlight_uid += 1
	token.set_meta("__highlight_uid", uid)
	if inst_id != 0:
		token.set_meta("__highlight_uid_owner", inst_id)
	return uid

func _reset_effect_tracking_for_token(token) -> void:
	var uid := _ensure_token_uid(token)
	if uid == 0:
		return
	_effect_targets[uid] = {"targets": [], "target_controls": [], "source_token": token, "source_controls": []}

func _prepare_effect_tracking(token: Variant) -> Dictionary:
	var uid := _ensure_token_uid(token)
	if uid == 0:
		return {}
	var entry_var: Variant = _effect_targets.get(uid)
	var entry: Dictionary = entry_var if entry_var is Dictionary else {}
	if entry.is_empty():
		entry = {"targets": [], "target_controls": [], "source_token": token, "source_controls": []}
		_effect_targets[uid] = entry
	else:
		entry["source_token"] = token
	if not entry.has("target_controls"):
		entry["target_controls"] = []
	if not entry.has("source_controls"):
		entry["source_controls"] = []
	var src_controls = _get_controls_for_uid(uid)
	_append_control_refs(entry, "source_controls", src_controls)
	return entry

func _register_effect_target(source_token: Variant, target_token: Variant) -> void:
	if source_token == null or target_token == null:
		return
	var entry: Dictionary = _prepare_effect_tracking(source_token)
	if entry.is_empty():
		return
	var target_uid := _ensure_token_uid(target_token)
	if target_uid == 0:
		return
	var targets_var: Variant = entry.get("targets", [])
	var targets: Array = targets_var if targets_var is Array else []
	if not targets.has(target_uid):
		targets.append(target_uid)
	entry["targets"] = targets
	var target_controls = _get_controls_for_uid(target_uid)
	_append_control_refs(entry, "target_controls", target_controls)

func _register_effect_target_current(target_token: Variant) -> void:
	if _current_effect_source == null:
		return
	if _current_effect_source != target_token:
		_register_effect_target(_current_effect_source, target_token)

func register_token_control(token: Variant, control: Control) -> void:
	_register_token_control(token, control)

func unregister_token_control(token: Variant, control: Control) -> void:
	_unregister_token_control(token, control)

func _register_token_control(token: Variant, control: Control) -> void:
	if token == null or control == null:
		return
	var uid := _ensure_token_uid(token)
	if uid == 0:
		return
	var list: Array = _token_controls.get(uid, [])
	list = _cleanup_token_controls(uid, list)
	var ref: WeakRef = weakref(control)
	for existing in list:
		if existing is WeakRef and existing.get_ref() == control:
			return
	list.append(ref)
	_token_controls[uid] = list
	control.set_meta("__highlight_uid", uid)
	var entry_var = _effect_targets.get(uid)
	if entry_var is Dictionary:
		var entry: Dictionary = entry_var
		_append_control_refs(entry, "source_controls", [control])
	var child := control.get_node_or_null("slotItem")
	if child is Control:
		_register_token_control(token, child)

func _unregister_token_control(token: Variant, control: Control) -> void:

	if token == null or control == null:

		return

	var uid := _ensure_token_uid(token)

	if uid == 0:

		return

	var list: Array = _token_controls.get(uid, [])

	var cleaned: Array = []

	for existing in list:

		if not (existing is WeakRef):

			continue

		var ctrl: Variant = existing.get_ref()

		if ctrl == null:

			continue

		if ctrl == control:

			if control.has_meta("__highlight_uid"):

				control.set_meta("__highlight_uid", null)

			continue

		cleaned.append(existing)

	_token_controls[uid] = cleaned

	var child := control.get_node_or_null("slotItem")

	if child is Control:

		_unregister_token_control(token, child)




func _cleanup_token_controls(uid: int, list: Array = []) -> Array:
	var cleaned: Array = []
	for existing in list:
		if not (existing is WeakRef):
			continue
		var ctrl: Variant = existing.get_ref()
		if ctrl == null:
			continue
		cleaned.append(existing)
	_token_controls[uid] = cleaned
	var entry_var = _effect_targets.get(uid)
	if entry_var is Dictionary:
		var entry: Dictionary = entry_var
		_prune_control_refs(entry, "source_controls")
		_prune_control_refs(entry, "target_controls")
	return cleaned

func _get_controls_for_uid(uid: int) -> Array:
	var list: Array = _token_controls.get(uid, [])
	list = _cleanup_token_controls(uid, list)
	var controls: Array = []
	for existing in list:
		if not (existing is WeakRef):
			continue
		var ctrl: Variant = existing.get_ref()
		if ctrl is Control:
			controls.append(ctrl)
	return controls

func _controls_from_refs(refs_variant) -> Array:
	var out: Array = []
	if refs_variant is Array:
		var refs: Array = refs_variant
		for ref in refs:
			if not (ref is WeakRef):
				continue
			var ctrl = ref.get_ref()
			if ctrl is Control:
				out.append(ctrl)
	return out

func _append_control_refs(entry: Dictionary, key: String, controls: Array) -> void:
	var refs_variant = entry.get(key, [])
	var refs: Array = refs_variant if refs_variant is Array else []
	var changed := false
	for ctrl in controls:
		if ctrl == null or not (ctrl is Control):
			continue
		var exists := false
		for ref in refs:
			if ref is WeakRef and ref.get_ref() == ctrl:
				exists = true
				break
		if exists:
			continue
		refs.append(weakref(ctrl))
		changed = true
	if changed:
		entry[key] = refs

func _prune_control_refs(entry: Dictionary, key: String) -> void:
	var refs_variant = entry.get(key, [])
	if not (refs_variant is Array):
		return
	var refs: Array = refs_variant
	var cleaned: Array = []
	for ref in refs:
		if not (ref is WeakRef):
			continue
		var ctrl = ref.get_ref()
		if ctrl is Control:
			cleaned.append(ref)
	entry[key] = cleaned

func start_effect_highlight_for_token(token: Variant) -> void:
	_kill_active_highlight()
	var uid := _ensure_token_uid(token)
	if uid == 0:
		return
	var entry_var: Variant = _effect_targets.get(uid)
	if entry_var == null:
		return
	var entry: Dictionary = entry_var if entry_var is Dictionary else {}
	if entry.is_empty():
		return
	var recorded_source = entry.get("source_token")
	if recorded_source != null and recorded_source != token:
		return
	var targets_var: Variant = entry.get("targets", [])
	var targets: Array = targets_var if targets_var is Array else []
	if targets.is_empty():
		return
	_active_effect_highlight = {"source": uid, "targets": targets.duplicate()}
	_start_highlight_flash(uid, targets)

func stop_effect_highlight_for_token(_token: Variant = null) -> void:
	_kill_active_highlight()

func _start_highlight_flash(source_uid: int, target_uids: Array) -> void:
	var controls: Array = []
	var entry: Dictionary = {}
	var entry_var = _effect_targets.get(source_uid)
	if entry_var is Dictionary:
		entry = entry_var
		_prune_control_refs(entry, "source_controls")
		_prune_control_refs(entry, "target_controls")
		var stored_source := _controls_from_refs(entry.get("source_controls", []))
		for ctrl in stored_source:
			if ctrl != null and not controls.has(ctrl):
				controls.append(ctrl)
		var stored_targets := _controls_from_refs(entry.get("target_controls", []))
		for ctrl in stored_targets:
			if ctrl != null and not controls.has(ctrl):
				controls.append(ctrl)
	var source_controls: Array = _get_controls_for_uid(source_uid)
	for ctrl in source_controls:
		if ctrl != null and not controls.has(ctrl):
			controls.append(ctrl)
	if not entry.is_empty():
		_append_control_refs(entry, "source_controls", source_controls)
	for uid in target_uids:
		var uid_int := int(uid)
		if uid_int == source_uid:
			continue
		var target_controls: Array = _get_controls_for_uid(uid_int)
		for ctrl in target_controls:
			if ctrl != null and not controls.has(ctrl):
				controls.append(ctrl)
		if not entry.is_empty():
			_append_control_refs(entry, "target_controls", target_controls)
	if controls.is_empty():
		return
	var unique_controls: Array = []
	for ctrl in controls:
		if ctrl != null and not unique_controls.has(ctrl):
			unique_controls.append(ctrl)
	_highlight_tweens.clear()
	var entries: Array = []
	for ctrl in unique_controls:
		if not (ctrl is CanvasItem):
			continue
		var base_color: Color = ctrl.modulate
		var entry_dict := {"control": ctrl, "base": base_color}
		entries.append(entry_dict)
		var tween := create_tween()
		tween.set_loops(0)
		_highlight_tweens.append(tween)
		tween.tween_property(ctrl, "modulate", highlight_flash_color, max(0.01, highlight_flash_in_sec)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(ctrl, "modulate", base_color, max(0.01, highlight_flash_out_sec)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		if highlight_flash_pause_sec > 0.0:
			tween.tween_interval(highlight_flash_pause_sec)
	_active_effect_highlight["entries"] = entries

func _kill_active_highlight() -> void:
	for tween in _highlight_tweens:
		if tween != null and tween is Tween:
			tween.kill()
	_highlight_tweens.clear()
	if _active_effect_highlight.has("entries"):
		for entry in _active_effect_highlight["entries"]:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var ctrl = entry.get("control")
			var base_color = entry.get("base")
			if is_instance_valid(ctrl) and base_color is Color:
				ctrl.modulate = base_color
	_active_effect_highlight.clear()

func _collect_token_tags(tok) -> Array:
	var out: Array = []
	if tok == null or not tok.has_method("get"):
		return out
	var tags = tok.get("tags")
	if tags is Array:
		for s in tags:
			if typeof(s) == TYPE_STRING:
				var norm := String(s).strip_edges().to_lower()
				if norm != "":
					out.append(norm)
	elif typeof(tags) == TYPE_PACKED_STRING_ARRAY:
		var psa: PackedStringArray = tags
		for s in psa:
			var norm2 := String(s).strip_edges().to_lower()
			if norm2 != "":
				out.append(norm2)
	return out

func _normalize_token_name(name: String) -> String:
	return String(name).strip_edges().to_lower()

func _compute_permanent_offset(tok) -> int:
	var key := _token_key(tok)
	var total := int(_token_value_offsets.get(key, 0))
	if _token_global_offset != 0:
		total += _token_global_offset
	if not _token_name_offsets.is_empty():
		var nm := _normalize_token_name(_token_name(tok))
		if nm != "":
			total += int(_token_name_offsets.get(nm, 0))
	if not _token_tag_offsets.is_empty():
		for tag in _collect_token_tags(tok):
			total += int(_token_tag_offsets.get(tag, 0))
	return total

# ---------- ability field helpers ----------
func _ability_is_active_during_spin(ab) -> bool:
	if ab == null:
		return false
	if (ab as Object).has_method("is_active_during_spin"):
		return bool(ab.is_active_during_spin())
	var trig = ab.get("trigger")
	var s := ""
	if typeof(trig) == TYPE_STRING:
		s = String(trig).to_lower()
		return s.findn("active") != -1 and s.findn("spin") != -1
	elif typeof(trig) == TYPE_INT:
		# TokenAbility.Trigger enum: 0 = ACTIVE_DURING_SPIN, 1 = ON_ACQUIRE
		return int(trig) == 0
	var flag = ab.get("active_during_spin")
	if flag != null:
		return bool(flag)
	return false

func _ability_winner_only(ab) -> bool:
	var v = ab.get("winner_only")
	if v != null:
		return bool(v)
	v = ab.get("WinnerOnly")
	if v != null:
		return bool(v)
	v = ab.get("winnerOnly")
	if v != null:
		return bool(v)
	return false

func _ability_target_kind(ab) -> String:
	var v = ab.get("target_kind")
	if typeof(v) == TYPE_STRING:
		return String(v)
	if typeof(v) == TYPE_INT:
		# TokenAbility.TargetKind enum: 0 SELF,1 MIDDLE,2 OFFSET,3 TAG,4 NAME,5 ANY
		match int(v):
			0: return "self"
			1: return "middle"
			2: return "offset"
			3: return "tag"
			4: return "name"
			5: return "any"
		return "self"
	v = ab.get("TargetKind")
	if typeof(v) == TYPE_STRING:
		return String(v)
	return "self"

func _ability_factor(ab) -> float:
	var v = ab.get("factor")
	if v != null:
		return float(v)
	if (ab as Object).has_method("get_factor"):
		return float(ab.get_factor())
	return 1.0

func _ability_amount(ab) -> int:
	var v = ab.get("amount")
	if v != null:
		return int(v)
	if (ab as Object).has_method("get_amount"):
		return int(ab.get_amount())
	return 0

func _ability_desc(ab, factor: float, amount: int, token) -> String:
	var tpl = ab.get("desc_template")
	var from := _token_name(token)
	if typeof(tpl) == TYPE_STRING:
		var s := String(tpl)
		if s.find("%s") != -1 and s.find("%f") != -1:
			return s % [factor, from]
		if s.find("%f") != -1:
			return s % [factor]
		if s.find("%d") != -1:
			return s % [amount]
		return s
	if amount != 0:
		return "+%d from %s" % [amount, from]
	return "x%.2f from %s" % [factor, from]

func _ability_id_or_class(ab) -> String:
	var idv = ab.get("id")
	if idv != null:
		return String(idv)
	if (ab as Object).has_method("get_id"):
		return String(ab.get_id())
	return _obj_name(ab)

func _obj_name(o) -> String:
	if o == null:
		return "null"
	if (o as Object).has_method("get_class"):
		return String((o as Object).get_class())
	return str(o)

# ---------- common ----------
func _pause(sec: float) -> Signal:
	return get_tree().create_timer(max(sec, 0.0)).timeout

func _mk_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r

func _safe_int(obj, prop: String, def: int) -> int:
	if obj == null:
		return def
	if obj.has_method("get"):
		var v = obj.get(prop)
		if v != null:
			return int(v)
	return def

# ---------- UI owner / resolve ----------
func _owner_node() -> Node:
	var target: Node = _totals_owner
	if target == null:
		target = get_tree().current_scene
	return target

func _resolve_spin_root() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		var sr = scene.find_child("spinRoot", true, false)
		if sr != null:
			return sr
	var root := get_tree().get_root()
	if root != null:
		var node := root.get_node_or_null("spinRoot")
		if node != null:
			return node
	return null

func _resolve_ui_node(start: Node, unique_name: String, plain_name: String) -> Node:
	if start == null:
		return null
	var n := start.get_node_or_null(unique_name)
	if n != null:
		return n
	return start.get_node_or_null(plain_name)

func _resolve_value_label() -> Node:
	if _value_label != null and is_instance_valid(_value_label):
		return _value_label
	_value_label = _resolve_ui_node(_owner_node(), "%valueLabel", "valueLabel")
	return _value_label

func _set_node_text(node: Node, txt: String) -> void:
	if node is Label:
		(node as Label).set_deferred("text", txt)
	elif node is RichTextLabel:
		(node as RichTextLabel).set_deferred("text", txt)
	else:
		node.set_deferred("text", txt)

# ---------- FX overlay helpers ----------

# Apply all winner global steps to all matching tokens simultaneously (single shared delay)
# Apply all winner global steps to all matching tokens simultaneously (single shared delay)
func _apply_global_steps_broadcast(global_steps: Array, contribs: Array, ctx: Dictionary, winner) -> void:
	_shake_active_effect_label()
	var prev_effect_source: Variant = _current_effect_source
	if winner != null:
		_prepare_effect_tracking(winner)
		_current_effect_source = winner
	await _pause(active_desc_pause_sec)

	# After the active effect label shake, run any board-visual commands (e.g., Mint replacing coins on board)
	var __board_cmds = ctx.get("__board_visual_cmds")
	if __board_cmds is Array and not (__board_cmds as Array).is_empty():
		if debug_spin:
			print("[Board-Visual] Executing ", int((__board_cmds as Array).size()), " command(s) after shake")
		_execute_ability_commands(__board_cmds, ctx, contribs, winner)

	# Also run any post-shake inventory commands (e.g., Hustler permanent_add) before totals
	var __post_cmds = ctx.get("__post_shake_cmds")
	if __post_cmds is Array and not (__post_cmds as Array).is_empty():
		if debug_spin:
			print("[Post-Shake] Executing ", int((__post_cmds as Array).size()), " inventory command(s)")
		_execute_ability_commands(__post_cmds, ctx, contribs, winner)

		# Important: some post-shake commands (e.g., permanent_add) adjust per-run offsets.
		# Ensure any tokens already shown on the board (created by board-visual commands)
		# have their base values re-initialized to include the new offsets.
		_refresh_all_slot_token_values(ctx)

		# Visual confirmation: if a self-target permanent_add was applied by the winner, show +amt on each same-type token
		var self_amt: int = 0
		for cmd in (__post_cmds as Array):
			if typeof(cmd) != TYPE_DICTIONARY:
				continue
			var d := cmd as Dictionary
			var op := String(d.get("op", "")).to_lower()
			if op != "permanent_add":
				continue
			var tk := String(d.get("target_kind", "")).to_lower()
			var toff := int(d.get("target_offset", 999))
			if tk == "self" or (tk == "offset" and toff == 0):
				self_amt += int(d.get("amount", 0))
		if self_amt != 0 and winner != null:
			var k := _token_key(winner)
			for i in range(contribs.size()):
				var c2: Dictionary = contribs[i]
				if _token_key(c2.get("token")) != k:
					continue
				# Avoid double visual on the winner; winner already shows its own adjustment via resync later.
				if int(c2.get("offset", 0)) == 0:
					continue
				var pv: int = _compute_value(c2)
				var nv: int = pv + self_amt
				_play_counting_popup(ctx, c2, pv, nv, false, {})
				# Update inline slot value if available
				var slot2 := _slot_from_ctx(ctx, int(c2.get("offset", 0)))
				if slot2 != null:
					var si2 := slot2.get_node_or_null("slotItem")
					if si2 != null and si2.has_method("set_value"):
						si2.call_deferred("set_value", nv)

	# Build per-target filtered step lists
	var targets: Array = []
	var steps_by_index: Dictionary = {}  # idx -> Array[Dictionary]
	for i in range(contribs.size()):
		var c: Dictionary = contribs[i]
		if _is_contrib_zero_replaced(c):
			continue
		var lst: Array = []
		for gs in global_steps:
			var stepn: Dictionary = _normalize_step(gs)
			if not _global_step_matches(stepn, c, winner):
				continue
			var filtered = _filter_step_for_contrib(ctx, stepn, winner, c)
			if typeof(filtered) == TYPE_DICTIONARY:
				lst.append(filtered)
		if not lst.is_empty():
			targets.append(i)
			steps_by_index[i] = lst

	if targets.is_empty():
		_current_effect_source = prev_effect_source
		return

	# Snapshot previous values per target
	var prev_vals: Dictionary = {}  # idx -> int
	var shake_by_index: Dictionary = {}
	for i in targets:
		var idx := int(i)
		var c: Dictionary = contribs[idx]
		prev_vals[idx] = _compute_value(c)

	# Apply all steps to each target (mutate first; no awaits)
	for i in targets:
		var idx := int(i)
		var c: Dictionary = contribs[idx]
		var lst: Array = steps_by_index[idx]
		if debug_spin:
			print("  [Final-Active/Broadcast] offset=", c.offset, " steps=", lst.size())
		for stepn in lst:
			if debug_spin:
				print("	[Apply] offset=", c.offset, " kind=", stepn.get("kind"), " +", stepn.get("amount", 0), " x", stepn.get("factor", 1.0), " src=", stepn.get("source", "winner_active"))
			var prev_val := _compute_value(c)
			_apply_step(c, stepn)
			var base_new_val := _compute_value(c)
			_invoke_on_value_changed(ctx, winner, c, prev_val, base_new_val, stepn)
			if _current_effect_source != null and String(stepn.get("source", "")).begins_with("ability:"):
				var target_token: Variant = c.get("token")
				if target_token != null:
					if _current_effect_source != target_token:
						_register_effect_target(_current_effect_source, target_token)
			var new_val := _compute_value(c)
			var delta := new_val - prev_val
			var shake_mag := 0.0
			if delta >= screen_shake_heavy_threshold:
				shake_mag = screen_shake_heavy_intensity
			elif delta >= screen_shake_moderate_threshold:
				shake_mag = screen_shake_moderate_intensity
			elif delta >= screen_shake_light_threshold:
				shake_mag = screen_shake_light_intensity
			if shake_mag > 0.0:
				var existing := float(shake_by_index.get(idx, 0.0))
				if shake_mag > existing:
					shake_by_index[idx] = shake_mag

	# Emit and update visuals for all targets in same frame
	for i in targets:
		var idx := int(i)
		var c: Dictionary = contribs[idx]
		if _is_contrib_zero_replaced(c):
			continue
		var new_val := _compute_value(c)

		var batch_step := {
			"kind": "batch",
			"amount": 0,
			"factor": 1.0,
			"desc": "winner_active_broadcast",
			"source": "winner_active"
		}
		emit_signal("token_step_applied", idx, c.offset, batch_step, new_val, c)
		emit_signal("token_value_shown", idx, c.offset, new_val, c)

		var slot := _slot_from_ctx(ctx, int(c.offset))
		if slot != null:
			var si := slot.get_node_or_null("slotItem")
			if si != null and si.has_method("set_value"):
				si.call_deferred("set_value", new_val)

	# Kick popups and shakes for all targets together
	for i in targets:
		var idx := int(i)
		var c: Dictionary = contribs[idx]
		if _is_contrib_zero_replaced(c):
			continue
		_play_counting_popup(ctx, c, int(prev_vals[idx]), _compute_value(c), false, {})
		var shake_mag := float(shake_by_index.get(idx, 0.0))
		if shake_mag > 0.0:
			_shake_slot_for_contrib(ctx, c)
			await _apply_screen_shake(shake_mag, screen_shake_duration)

	# Replace any tokens that hit zero during broadcast steps
	for i in targets:
		var idx := int(i)
		var c: Dictionary = contribs[idx]
		if _is_contrib_zero_replaced(c):
			continue
		_maybe_replace_contrib_with_empty(ctx, c, int(prev_vals.get(idx, 0)), _compute_value(c), "broadcast")

	await _pause(step_delay_sec)
		
# Shake the active effect description label to match token feedback
func _shake_active_effect_label() -> void:
	var lbl := _resolve_active_effect_label()
	if lbl == null:
		return
	if not (lbl is CanvasItem):
		return
	var ci := lbl as CanvasItem
	var base_mod := ci.modulate

	# Flash alpha similar to slot highlight
	var fx := get_tree().create_tween()
	fx.tween_property(ci, "modulate", Color(base_mod.r, base_mod.g, base_mod.b, 0.90), 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fx.chain().tween_property(ci, "modulate", base_mod, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Shake effect if it's a Control (rotation to avoid layout shifts)
	if ci is Control:
		var ctrl := ci as Control
		var rng := _mk_rng()
		var meta_key := "__active_effect_shake"
		if ctrl.has_meta(meta_key):
			var prev_state = ctrl.get_meta(meta_key)
			if typeof(prev_state) == TYPE_DICTIONARY:
				var prev_tween = prev_state.get("tween")
				if prev_tween != null and prev_tween is Object:
					var tween_obj := prev_tween as Object
					if tween_obj.has_method("kill"):
						tween_obj.call("kill")
				if prev_state.has("pivot"):
					ctrl.pivot_offset = prev_state["pivot"]
				if prev_state.has("rotation"):
					ctrl.rotation = prev_state["rotation"]
			ctrl.remove_meta(meta_key)
		var orig_pivot := ctrl.pivot_offset
		var orig_rotation := ctrl.rotation
		var size := ctrl.size
		if size != Vector2.ZERO:
			ctrl.pivot_offset = size * 0.5
		var shake := get_tree().create_tween()
		var state := {
			"pivot": orig_pivot,
			"rotation": orig_rotation,
			"tween": shake
		}
		ctrl.set_meta(meta_key, state)
		var shakes := 3
		var rotation_strength: float = deg_to_rad(2.5)
		for i in range(shakes):
			var angle := rng.randf_range(-rotation_strength, rotation_strength)
			shake.tween_property(ctrl, "rotation", angle, 0.03).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		shake.tween_property(ctrl, "rotation", orig_rotation, 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		shake.finished.connect(func():
			ctrl.rotation = orig_rotation
			ctrl.pivot_offset = orig_pivot
			ctrl.remove_meta(meta_key)
		)

# Rarity-driven unique picks: choose rarity by adjusted weights, then choose a token within that rarity using token.weight.
func _pick_with_rarity_schedule(
	pool: Array,
	count: int,
	rng: RandomNumberGenerator,
	round_num: int,
	sched: LootRaritySchedule,
	weights_override: Dictionary = {}
) -> Array:
	var result: Array = []
	if pool.is_empty() or count <= 0:
		return result

	# Build rarity -> tokens[] buckets (only tokens with weight > 0 participate)
	var buckets: Dictionary = {}  # rarity (String) -> Array
	for t in pool:
		if t == null or not t.has_method("get"):
			continue
		var wv = t.get("weight")
		var wnum: float = 1.0
		if wv != null:
			wnum = float(wv)
		if wnum <= 0.0:
			continue
		var r = t.get("rarity")
		var key: String = "common"
		if r != null:
			key = String(r).to_lower()
		if not buckets.has(key):
			buckets[key] = []
		var arr: Array = buckets[key]
		arr.append(t)
		buckets[key] = arr

	# Determine rarity weights (override > schedule), normalized
	var weights: Dictionary = weights_override if not weights_override.is_empty() else sched.get_rarity_weights(round_num)
	weights = _normalize_weights(weights)

	# Prepare ordered rarities for fallback when chosen bucket is empty
	var ordered_rarities: Array[String] = []
	for k in weights.keys():
		ordered_rarities.append(String(k))
	ordered_rarities.sort_custom(func(a: String, b: String) -> bool:
		return float(weights[a]) > float(weights[b])
	)

	var picks: int = min(count, pool.size())
	for i in range(picks):
		# Pick a rarity using the adjusted weights (token.weight does NOT affect this choice)
		var desired: String = _weighted_choice_by_map(weights, rng)
		var chosen_rarity: String = desired

		# Fallback to next most likely rarity that still has tokens
		if not buckets.has(chosen_rarity) or (buckets[chosen_rarity] as Array).is_empty():
			for alt in ordered_rarities:
				if buckets.has(alt) and not (buckets[alt] as Array).is_empty():
					chosen_rarity = alt
					break

		# If no rarities have tokens left, stop
		if not buckets.has(chosen_rarity) or (buckets[chosen_rarity] as Array).is_empty():
			break

		# Pick within chosen rarity using per-token weight (debug/artifact-friendly)
		var bucket: Array = buckets[chosen_rarity]
		var token: Variant = _weighted_choice(bucket, rng)  # reads token.get("weight"), default 1.0
		if token == null:
			break

		result.append(token)

		# Unique picks: remove from its bucket
		bucket.erase(token)
		if bucket.is_empty():
			buckets.erase(chosen_rarity)
		else:
			buckets[chosen_rarity] = bucket

	return result
	
func _active_rarity_schedule() -> LootRaritySchedule:
	var sched: LootRaritySchedule = loot_rarity_schedule
	if sched == null:
		# Try an autoload named LootRarityManager
		var mgr := get_node_or_null("/root/LootRarityManager")
		if mgr != null and mgr.has_method("get_active_schedule"):
			sched = mgr.get_active_schedule()
	return sched

# Example modifier: +3% non-common per Empty. Returns normalized weights.
func _apply_rarity_modifiers(base_weights: Dictionary, round_num: int, rng: RandomNumberGenerator) -> Dictionary:
	var w: Dictionary = {}  # lowercased keys
	for k in base_weights.keys():
		var key: String = String(k).to_lower()
		var v: float = float(base_weights[k])
		w[key] = v

	# Empties bonus: shift mass from 'common' into non-common
	var empties: int = _count_empties()
	if empties > 0 and empty_non_common_bonus_per > 0.0:
		var delta: float = float(empties) * float(empty_non_common_bonus_per)
		var common: float = float(w.get("common", 0.0))
		var move: float = clamp(delta, 0.0, common)
		if move > 0.0:
			var non_keys: Array[String] = []
			var non_sum: float = 0.0
			for k in w.keys():
				var kk: String = String(k)
				if kk != "common":
					non_keys.append(kk)
					non_sum += max(0.0, float(w[kk]))
			w["common"] = common - move
			if non_keys.size() > 0:
				if non_sum <= 0.0:
					var split: float = move / float(non_keys.size())
					for nk in non_keys:
						w[nk] = max(0.0, float(w.get(nk, 0.0))) + split
				else:
					for nk in non_keys:
						var share: float = max(0.0, float(w[nk])) / non_sum
						w[nk] = max(0.0, float(w[nk])) + move * share

	# Optional manager hook for additional roguelike tier ramps and effects
	var mgr: Node = get_node_or_null("/root/LootRarityManager")
	if mgr != null and mgr.has_method("apply_modifiers"):
		var ctx: Dictionary = {
			"round": round_num,
			"rng": rng,
			"empty_count": empties,
			"artifacts": _artifacts,
			"run_index": spin_index
		}
		var modified = mgr.call("apply_modifiers", _normalize_weights(w), ctx)
		if typeof(modified) == TYPE_DICTIONARY:
			w = modified

	return _normalize_weights(w)

func _normalize_weights(weights: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var sum: float = 0.0
	for k in weights.keys():
		var key: String = String(k).to_lower()
		var v: float = max(0.0, float(weights[k]))
		out[key] = v
		sum += v
	if sum <= 0.0:
		var keys: Array = out.keys()
		var eq: float = 1.0 / float(max(1, keys.size()))
		for key in keys:
			out[String(key)] = eq
	else:
		for key in out.keys():
			var sk: String = String(key)
			out[sk] = float(out[sk]) / sum
	return out

func _count_empties() -> int:
	var arr: Array = _get_inventory_array()
	var c: int = 0
	for t in arr:
		if _is_empty_token(t):
			c += 1
	return c

# Normalize a step dictionary to expected fields
func _normalize_step(d: Dictionary) -> Dictionary:
	var out := {
		"kind": String(d.get("kind", "")),
		"amount": int(d.get("amount", 0)),
		"factor": float(d.get("factor", 1.0)),
		"desc": String(d.get("desc", "")),
		"source": String(d.get("source", "unknown")),
		"target_kind": String(d.get("target_kind", "")),
		"target_offset": int(d.get("target_offset", 0)),
		"target_tag": String(d.get("target_tag", "")),
		"target_name": String(d.get("target_name", ""))
	}
	if d.has("_ability_ref"):
		out["_ability_ref"] = d["_ability_ref"]
	if d.has("_stage"):
		out["_stage"] = String(d["_stage"])
	if d.has("min_value"):
		out["min_value"] = int(d["min_value"])
	if d.has("_temporary"):
		out["_temporary"] = bool(d["_temporary"])
	return out

# Normalize a "global" step (winner final-phase). Defaults target_kind to "any" if missing.
func _normalize_global_step(d: Dictionary) -> Dictionary:
	var s: Dictionary = _normalize_step(d)
	# If kind is missing but amount/factor indicate intent, infer it.
	if String(s.get("kind", "")).strip_edges() == "":
		var fac := float(s.get("factor", 1.0))
		var amt := int(s.get("amount", 0))
		if abs(fac - 1.0) > 0.0001:
			s["kind"] = "mult"
		elif amt != 0:
			s["kind"] = "add"
	# Ensure target fields exist; be permissive by default.
	if String(s.get("target_kind", "")).strip_edges() == "":
		s["target_kind"] = "any"
	return s

func _is_step_temporary(step: Dictionary) -> bool:
	if step == null:
		return false
	if step.has("_temporary"):
		return bool(step.get("_temporary", false))
	var kind := String(step.get("kind", ""))
	return kind == "add" or kind == "mult"

# Get abilities array from a token/resource if present
func _get_abilities(obj) -> Array:
	if obj == null:
		return []
	if obj.has_method("get"):
		var abilities = obj.get("abilities")
		if abilities is Array:
			return abilities
	return []

# Ability filter: let target/source abilities cancel or mutate a step
# Returns Dictionary (possibly mutated) to apply, or null/falsey to cancel.
# Ability filter: let target/source abilities cancel or mutate a step
# Returns Dictionary (possibly mutated) to apply, or null/falsey to cancel.
func _filter_step_for_contrib(ctx: Dictionary, step: Dictionary, source_token, target_contrib: Dictionary):
	var token_target = target_contrib.get("token")
	var abilities_sets: Array = [
		_get_abilities(token_target),
		_get_abilities(source_token)
	]
	var result: Dictionary = step
	for abilities in abilities_sets:
		for ab in abilities:
			if ab == null:
				continue

			# Strict winner_only gating: abilities marked winner_only only act on the winner slot (offset == 0)
			if _ability_winner_only(ab) and int(target_contrib.get("offset", 99)) != 0:
				if debug_spin:
					print("  [Ability] Skip filter_step (winner_only) for offset=", target_contrib.get("offset", "?"), " ab=", _obj_name(ab))
				continue

			if (ab as Object).has_method("filter_step"):
				var out = ab.call("filter_step", ctx, result, source_token, token_target, target_contrib)
				# Allow flexible returns:
				# - null/false -> cancel
				# - true -> keep unchanged
				# - Dictionary -> mutated step (unless {cancel=true})
				if out == null or (typeof(out) == TYPE_BOOL and out == false):
					return null
				if typeof(out) == TYPE_DICTIONARY:
					if bool((out as Dictionary).get("cancel", false)):
						return null
					result = _normalize_step(out)
	return result

# Ability on_value_changed: notify target and source ability sets
func _invoke_on_value_changed(ctx: Dictionary, source_token, target_contrib: Dictionary, prev_val: int, new_val: int, step: Dictionary) -> void:
	var token_target = target_contrib.get("token")
	var abilities_sets: Array = [
		_get_abilities(token_target),
		_get_abilities(source_token)
	]
	for abilities in abilities_sets:
		for ab in abilities:
			if ab == null:
				continue

			# Strict winner_only gating: abilities marked winner_only only react on the winner slot (offset == 0)
			if _ability_winner_only(ab) and int(target_contrib.get("offset", 99)) != 0:
				if debug_spin:
					print("  [Ability] Skip on_value_changed (winner_only) for offset=", target_contrib.get("offset", "?"), " ab=", _obj_name(ab))
				continue

			if (ab as Object).has_method("on_value_changed"):
				ab.call("on_value_changed", ctx, prev_val, new_val, source_token, token_target, target_contrib, step)

# ---------- Ability command collection/execution ----------
func _collect_winner_ability_commands(ctx: Dictionary, contribs: Array, winner) -> Array:
	var out: Array = []
	if not (contribs is Array):
		return out
	var winner_token = null
	if winner != null and winner.has_method("get"):
		winner_token = winner
	# Allow non-winner abilities (winner_only = false) to emit inventory commands
	for raw in contribs:
		if not (raw is Dictionary):
			continue
		var contrib: Dictionary = raw
		var token = contrib.get("token")
		if token == null or not token.has_method("get"):
			continue
		var abilities = token.get("abilities")
		if not (abilities is Array):
			continue
		var is_winner_token: bool = int(contrib.get("offset", 99)) == 0
		for ab in abilities:
			if ab == null:
				continue
			if not _ability_is_active_during_spin(ab):
				continue
			var requires_winner := _ability_winner_only(ab)
			if requires_winner:
				if not is_winner_token:
					continue
			if (ab as Object).has_method("build_commands"):
				var arr = ab.build_commands(ctx, contribs, token)
				if arr is Array:
					for cmd in arr:
						if typeof(cmd) == TYPE_DICTIONARY:
							var cmd_dict: Dictionary = (cmd as Dictionary).duplicate(true)
							cmd_dict["__effect_source_token"] = token
							cmd_dict["__ability_ref"] = ab
							if not cmd_dict.has("source"):
								cmd_dict["source"] = "ability:" + _ability_id_or_class(ab)
							out.append(cmd_dict)
	return out

func _execute_ability_commands(cmds: Array, ctx: Dictionary, _contribs: Array, effect_source: Variant = null) -> void:
	# Share current contribs for abilities that need adjacency info
	if ctx is Dictionary:
		ctx["__last_contribs"] = _contribs
	# Pre-pass: register guards so subsequent destructive ops are blocked within this batch
	for c0 in cmds:
		if typeof(c0) != TYPE_DICTIONARY:
			continue
		var op0 := String((c0 as Dictionary).get("op", "")).to_lower()
		if op0 == "register_guard_aura":
			_register_guard_offset(ctx, int((c0 as Dictionary).get("offset", 0)))
		elif op0 == "register_destroy_guard":
			_register_value_guard(ctx,
				int((c0 as Dictionary).get("offset", 0)),
				int((c0 as Dictionary).get("min_value_threshold", 0)),
				bool((c0 as Dictionary).get("triggered_only", true)))
		elif op0 == "register_ward":
			_register_ward_offset(ctx, int((c0 as Dictionary).get("offset", 0)))
	var __choose_ordinal: int = 0
	for cmd in cmds:
		if typeof(cmd) != TYPE_DICTIONARY:
			continue
		var cmd_source: Variant = effect_source
		if (cmd as Dictionary).has("__effect_source_token"):
			cmd_source = (cmd as Dictionary)["__effect_source_token"]
		var prev_effect_source: Variant = _current_effect_source
		if cmd_source != null:
			_prepare_effect_tracking(cmd_source)
			_current_effect_source = cmd_source
		var op := String((cmd as Dictionary).get("op", "")).to_lower()
		# Handle interactive targeting: mark choose → resolve an offset from UI
		if _op_needs_offset(op):
			var need_choose := String((cmd as Dictionary).get("target_kind", "")) == "choose" or bool((cmd as Dictionary).get("choose", false))
			if need_choose:
				_target_selection_pending = true
				_notify_spin_lock_state(ctx)
				__choose_ordinal += 1
				var off_choice := await _prompt_target_offset(ctx, true, __choose_ordinal)
				_target_selection_pending = false
				_notify_spin_lock_state(ctx)
				(cmd as Dictionary)["offset"] = int(off_choice)
				(cmd as Dictionary)["target_offset"] = int(off_choice)
		# Ward redirection: if an adjacent ward exists, redirect destructive ops to the ward instead
		if op == "destroy" or op == "destroy_and_gain_fraction" or op == "replace_at_offset":
			var off_in := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
			var off_out := _resolve_ward_redirect(ctx, _contribs, off_in)
			(cmd as Dictionary)["offset"] = int(off_out)
			(cmd as Dictionary)["target_offset"] = int(off_out)
		match op:
			"copy_target_to_inventory":
				var offci := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				var target_ci := _find_contrib_by_offset(_contribs, offci)
				if target_ci.is_empty():
					continue
				var tok_ci = target_ci.get("token")
				if tok_ci == null or not (tok_ci as Object).has_method("duplicate"):
					continue
				var arr_ci := _get_inventory_array()
				var idx_emp_ci := _find_empty_index(arr_ci)
				var dup_ci := (tok_ci as Resource).duplicate(true)
				_init_token_base_value(dup_ci)
				if idx_emp_ci >= 0:
					arr_ci[idx_emp_ci] = dup_ci
				else:
					arr_ci.append(dup_ci)
				_set_inventory_array(arr_ci)
			"replace_at_offset_from_choices":
				var offc2 := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				var tpaths: Variant = (cmd as Dictionary).get("token_paths", [])
				var pick_path: String = ""
				if tpaths is Array:
					var arrp: Array = tpaths
					if arrp.size() > 0:
						pick_path = String(arrp[_loot_rng.randi_range(0, arrp.size()-1)])
				if pick_path.strip_edges() == "":
					continue
				_replace_token_at_offset(ctx, offc2, pick_path, -1, false)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"replace_self_with_random_inventory":
				# Find self offset
				var self_c_rs := _find_self_contrib(_contribs, effect_source)
				if self_c_rs.is_empty():
					continue
				var offrs := int(self_c_rs.get("offset", 0))
				if _guard_blocks(ctx, _contribs, offrs, op):
					if debug_spin: print("[Guard] Blocked replace_self_with_random_inventory at ", offrs)
					continue
				var inv_arr := _get_inventory_array()
				var candidates: Array = []
				for tok in inv_arr:
					if tok == null or not (tok as Object).has_method("get"):
						continue
					if _token_name(tok) == "Empty":
						continue
					candidates.append(tok)
				if candidates.is_empty():
					continue
				var pick_tok = candidates[_loot_rng.randi_range(0, candidates.size()-1)]
				_replace_token_at_offset(ctx, offrs, "", -1, false, null, pick_tok)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"spawn_random_by_tag":
				var tag_sr := String((cmd as Dictionary).get("target_tag", ""))
				var count_sr := max(1, int((cmd as Dictionary).get("count", 1)))
				var choices_sr: Array[String] = []
				var troot_sr := String(loot_scan_root)
				var da_sr = DirAccess.open(troot_sr)
				if da_sr != null:
					var files = da_sr.get_files()
					for f in files:
						if f.ends_with(".tres"):
							var p: String = troot_sr.path_join(f)
							var res = ResourceLoader.load(p)
							if res != null and (res as Object).has_method("get") and _token_has_tag(res, tag_sr):
								choices_sr.append(p)
				for i in range(count_sr):
					if choices_sr.is_empty():
						break
					var pck := choices_sr[_loot_rng.randi_range(0, choices_sr.size()-1)]
					var arrx := _get_inventory_array()
					var idx_emp2 := _find_empty_index(arrx)
					var resx = ResourceLoader.load(pck)
					if resx is Resource:
						var dupx := (resx as Resource).duplicate(true)
						_init_token_base_value(dupx)
						if idx_emp2 >= 0:
							arrx[idx_emp2] = dupx
						else:
							arrx.append(dupx)
						_set_inventory_array(arrx)
			"spawn_random_by_rarity":
				var rar_sr := String((cmd as Dictionary).get("rarity", "")).to_lower()
				var count_rr := max(1, int((cmd as Dictionary).get("count", 1)))
				var troot_rr := String(loot_scan_root)
				for i in range(count_rr):
					var p_rr := _pick_random_by_rarity_path(troot_rr, rar_sr)
					if p_rr.strip_edges() == "":
						break
					var arr_rr := _get_inventory_array()
					var idx_empr := _find_empty_index(arr_rr)
					var resr = ResourceLoader.load(p_rr)
					if resr is Resource:
						var dupr := (resr as Resource).duplicate(true)
						_init_token_base_value(dupr)
						if idx_empr >= 0:
							arr_rr[idx_empr] = dupr
						else:
							arr_rr.append(dupr)
						_set_inventory_array(arr_rr)
			"spawn_random_any":
				var count_any := max(1, int((cmd as Dictionary).get("count", 1)))
				var troot_any := String(loot_scan_root)
				var all_paths_any: Array[String] = _collect_token_paths_under(troot_any)
				var choices_any: Array[String] = []
				for pth in all_paths_any:
					var res_any = ResourceLoader.load(pth)
					if res_any == null or not (res_any as Object).has_method("get"):
						continue
					var nm_any := _token_name(res_any)
					if nm_any == "Empty":
						continue
					choices_any.append(pth)
				for i in range(count_any):
					if choices_any.is_empty():
						break
					var pick_any := choices_any[_loot_rng.randi_range(0, choices_any.size()-1)]
					var arr_any := _get_inventory_array()
					var idx_empa := _find_empty_index(arr_any)
					var resa = ResourceLoader.load(pick_any)
					if resa is Resource:
						var dupa := (resa as Resource).duplicate(true)
						_init_token_base_value(dupa)
						if idx_empa >= 0:
							arr_any[idx_empa] = dupa
						else:
							arr_any.append(dupa)
						_set_inventory_array(arr_any)
			"spawn_copy_of_last_destroyed":
				var count_l := max(1, int((cmd as Dictionary).get("count", 1)))
				var last_tok = null
				if ctx is Dictionary and ctx.has("last_destroyed_token"):
					last_tok = ctx["last_destroyed_token"]
				if last_tok == null or not (last_tok as Object).has_method("duplicate"):
					continue
				for i in range(count_l):
					var dup_l := (last_tok as Resource).duplicate(true)
					_init_token_base_value(dup_l)
					var arr_l := _get_inventory_array()
					var idx_empl := _find_empty_index(arr_l)
					if idx_empl >= 0:
						arr_l[idx_empl] = dup_l
					else:
						arr_l.append(dup_l)
					_set_inventory_array(arr_l)
			"destroy_lowest_triggered":
				var exclude_self := bool((cmd as Dictionary).get("exclude_self", true))
				var best_off := 999
				var best_val := 999999
				for c in _contribs:
					if not (c is Dictionary):
						continue
					var offl := int((c as Dictionary).get("offset", 99))
					if offl == 0 and exclude_self:
						continue
					var tok = (c as Dictionary).get("token")
					if tok == null or not (tok as Object).has_method("get"):
						continue
					var name := _token_name(tok)
					if name == "Empty":
						continue
					var v := _compute_value(c)
					if v < best_val:
						best_val = v
						best_off = offl
				if best_off != 999:
					if _guard_blocks(ctx, _contribs, best_off, op):
						continue
					var empty_res7 := _load_empty_token()
					if empty_res7 is Resource:
						_replace_token_at_offset(ctx, best_off, (empty_res7 as Resource).resource_path, -1, false)
						_resync_contribs_from_board(ctx, _contribs)
						_refresh_dynamic_passives(ctx, _contribs)
			"trigger_loot_selection":
				var spr = max(spins_per_round, 1)
				var round_num := int(spin_index / spr)
				var started := _trigger_loot_choice(round_num, true, ctx)
				if started:
					while _loot_selection_pending:
						await get_tree().process_frame
				else:
					_notify_spin_lock_state(ctx)
			"spawn_copy_in_inventory":
				var to_copy = (cmd as Dictionary).get("token_ref", null)
				if to_copy != null and (to_copy is Resource or (to_copy as Object).has_method("duplicate")):
					var arr := _get_inventory_array()
					var idx_emp := _find_empty_index(arr)
					var dup := (to_copy as Resource).duplicate(true)
					_init_token_base_value(dup)
					if idx_emp >= 0:
						arr[idx_emp] = dup
					else:
						arr.append(dup)
					_set_inventory_array(arr)
			"destroy_all_copies_by_name":
				var nm := String((cmd as Dictionary).get("token_name", ""))
				if nm.strip_edges() != "":
					var arr2 := _get_inventory_array()
					var empty_res3 := _load_empty_token()
					if empty_res3 is Resource:
						var erp := (empty_res3 as Resource).resource_path
						for i in range(arr2.size()):
							var it = arr2[i]
							if it != null and (it as Object).has_method("get") and String(it.get("name")) == nm:
								arr2[i] = (empty_res3 as Resource).duplicate(true)
						_set_inventory_array(arr2)
						_resync_contribs_from_board(ctx, _contribs)
						_refresh_dynamic_passives(ctx, _contribs)
			"destroy_triggered_tag":
				var tagd := String((cmd as Dictionary).get("target_tag", ""))
				for c in _contribs:
					if c is Dictionary and _token_has_tag((c as Dictionary).get("token"), tagd):
						var offd := int((c as Dictionary).get("offset", 0))
						if _guard_blocks(ctx, _contribs, offd, op):
							continue
						var empty_res4 := _load_empty_token()
						if empty_res4 is Resource:
							_replace_token_at_offset(ctx, offd, (empty_res4 as Resource).resource_path, -1, false)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"destroy_non_triggered_empties":
				var triggered_real: Array = []
				var triggered_null := 0
				for c in _contribs:
					if c is Dictionary:
						var tok = c.get("token")
						if _is_empty_token(tok):
							if tok == null:
								triggered_null += 1
							else:
								triggered_real.append(tok)
				var arr_em := _get_inventory_array()
				var new_arr: Array = []
				var changed := false
				for i in range(arr_em.size()):
					var tok_e = arr_em[i]
					var remove_this := false
					if _is_empty_token(tok_e):
						var skip := false
						if tok_e != null and triggered_real.has(tok_e):
							triggered_real.erase(tok_e)
							skip = true
						elif tok_e == null and triggered_null > 0:
							triggered_null -= 1
							skip = true
						if not skip:
							_notify_any_token_destroyed(ctx, tok_e, "destroy_non_triggered_empty")
							remove_this = true
					if remove_this:
						changed = true
						continue
					new_arr.append(tok_e)
				if changed:
					_set_inventory_array(new_arr)
					if ctx != null and ctx is Dictionary:
						(ctx as Dictionary)["board_tokens"] = _get_inventory_array()
					_resync_contribs_from_board(ctx, _contribs)
					_refresh_dynamic_passives(ctx, _contribs)
				continue

			"adjust_empty_rarity_bonus":
				var delta := float((cmd as Dictionary).get("amount", 0.0))
				if delta != 0.0:
					empty_non_common_bonus_per = max(0.0, empty_non_common_bonus_per + delta)
				continue
			"replace_self_random_by_tag":
				var tagrs := String((cmd as Dictionary).get("target_tag", ""))
				var sets := _class_allowed_sets(ctx)
				var troot := String((cmd as Dictionary).get("tokens_root", loot_scan_root))
				var choices: Array[String] = []
				var da = DirAccess.open(troot)
				if da != null:
					var files = da.get_files()
					for f in files:
						if f.ends_with(".tres"):
							var p: String = troot.path_join(f)
							var res = ResourceLoader.load(p)
							if res != null and (res as Object).has_method("get") and _token_has_tag(res, tagrs):
								if sets.is_empty():
									choices.append(p)
								else:
									var tags=res.get("tags")
									var ok=false
									if tags is Array:
										for t in tags:
											if typeof(t)==TYPE_STRING and sets.has(String(t)):
												ok=true; break
									if ok:
										choices.append(p)
				if not choices.is_empty():
					var pick := choices[_loot_rng.randi_range(0, choices.size()-1)]
					# Find self offset
					var self_c := _find_self_contrib(_contribs, effect_source)
					var off_self := 0
					if not self_c.is_empty(): off_self = int(self_c.get("offset", 0))
					_replace_token_at_offset(ctx, off_self, pick, -1, false)
					_resync_contribs_from_board(ctx, _contribs)
					_refresh_dynamic_passives(ctx, _contribs)
			"promote_token_in_inventory":
				var pathp := String((cmd as Dictionary).get("token_path", ""))
				var from_ref: Variant = (cmd as Dictionary).get("from_ref", null)
				if pathp.strip_edges() == "":
					break
				var arr3: Array = _get_inventory_array()
				var idxp := -1
				if from_ref != null:
					for i in range(arr3.size()):
						if arr3[i] == from_ref:
							idxp = i; break
				if idxp == -1 and from_ref != null and (from_ref as Object).has_method("get"):
					var fn := String(from_ref.get("name"))
					for i in range(arr3.size()):
						var it2 = arr3[i]
						if it2 != null and (it2 as Object).has_method("get") and String(it2.get("name")) == fn:
							idxp = i; break
				if idxp >= 0:
					_replace_token_at_offset(ctx, 0, pathp, -1, false, arr3[idxp])
					_resync_contribs_from_board(ctx, _contribs)
					_refresh_dynamic_passives(ctx, _contribs)
			"spawn_token_in_inventory":
				var path_s := String((cmd as Dictionary).get("token_path", ""))
				var count := int((cmd as Dictionary).get("count", 1))
				if path_s.strip_edges() == "":
					break
				var res_s := ResourceLoader.load(path_s)
				if res_s is Resource:
					var arr4 := _get_inventory_array()
					var spawned: Array = []
					var to_spawn = max(1, count)
					for i in range(to_spawn):
						var dup2 := (res_s as Resource).duplicate(true)
						_init_token_base_value(dup2)
						_ensure_token_uid(dup2)
						var idxe := _find_empty_index(arr4)
						if idxe >= 0:
							arr4[idxe] = dup2
						else:
							arr4.append(dup2)
						spawned.append(dup2)
					_set_inventory_array(arr4)
					for new_tok in spawned:
						_register_effect_target_current(new_tok)
					var owner_now := _resolve_inventory_owner_node()
					if owner_now != null and owner_now.has_method("_update_inventory_strip"):
						owner_now.call_deferred("_update_inventory_strip")
					if ctx is Dictionary:
						ctx["board_tokens"] = _get_inventory_array()
						_refresh_dynamic_passives(ctx, _contribs)
			"register_guard_aura":
				var off_g := int((cmd as Dictionary).get("offset", 0))
				_register_guard_offset(ctx, off_g)
			"register_destroy_guard":
				var off_v := int((cmd as Dictionary).get("offset", 0))
				var thr := int((cmd as Dictionary).get("min_value_threshold", 0))
				var trg_only := bool((cmd as Dictionary).get("triggered_only", true))
				_register_value_guard(ctx, off_v, thr, trg_only)
			"register_ward":
				var off_w := int((cmd as Dictionary).get("offset", 0))
				_register_ward_offset(ctx, off_w)
			"replace_at_offset":
				var off := int((cmd as Dictionary).get("offset", 0))
				if _guard_blocks(ctx, _contribs, off, op):
					if debug_spin: print("[Guard] Blocked replace_at_offset at ", off)
					continue
				var token_path := String((cmd as Dictionary).get("token_path", ""))
				var set_value := int((cmd as Dictionary).get("set_value", -1))
				var preserve_tags := bool((cmd as Dictionary).get("preserve_tags", false))
				var token_ref = (cmd as Dictionary).get("token_ref", null)
				_replace_token_at_offset(ctx, off, token_path, set_value, preserve_tags, null, token_ref)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"replace_all_empties":
				var token_path2 := String((cmd as Dictionary).get("token_path", ""))
				_replace_all_empties_in_inventory(token_path2, ctx)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"permanent_add":
				var tk := String((cmd as Dictionary).get("target_kind", "any")).to_lower()
				var toff := int((cmd as Dictionary).get("target_offset", 0))
				var ttag := String((cmd as Dictionary).get("target_tag", ""))
				var tname := String((cmd as Dictionary).get("target_name", ""))
				var amt2 := int((cmd as Dictionary).get("amount", 0))
				var diz := bool((cmd as Dictionary).get("destroy_if_zero", false))
				var propagate_same_key := bool((cmd as Dictionary).get("propagate_same_key", false))
				_apply_permanent_add_inventory(tk, toff, ttag, tname, amt2, diz, ctx, propagate_same_key)
				if tk == "name":
					var name_norm := String(tname).strip_edges().to_lower()
					if name_norm != "":
						for contrib in _contribs:
							if not (contrib is Dictionary):
								continue
							var contrib_token = (contrib as Dictionary).get("token")
							if contrib_token == null or not (contrib_token as Object).has_method("get"):
								continue
							if _normalize_token_name(_token_name(contrib_token)) != name_norm:
								continue
							_init_token_base_value(contrib_token)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
				# After adjusting permanent offsets/inventory, re-initialize board slot token values
				_refresh_all_slot_token_values(ctx)
			"replace_board_tag":
				var tag := String((cmd as Dictionary).get("target_tag", ""))
				var tpath := String((cmd as Dictionary).get("token_path", ""))
				_replace_board_tag_in_slotmap(ctx, tag, tpath)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"replace_board_empties":
				var tpath2 := String((cmd as Dictionary).get("token_path", ""))
				_replace_board_empties_in_slotmap(ctx, tpath2)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"adjust_run_total":
				var amt := int((cmd as Dictionary).get("amount", 0))
				if amt != 0:
					total_coins = max(0, total_coins + amt)
					_update_totals_label(total_coins)
			"destroy":
				var off2 := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				if _guard_blocks(ctx, _contribs, off2, op):
					if debug_spin: print("[Guard] Blocked destroy at ", off2)
					continue
				var empty_res := _load_empty_token()
				if empty_res != null and empty_res is Resource:
					_replace_token_at_offset(ctx, off2, (empty_res as Resource).resource_path, -1, false)
					_resync_contribs_from_board(ctx, _contribs)
					_refresh_dynamic_passives(ctx, _contribs)
			"destroy_and_gain_fraction":
				var offx := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				if _guard_blocks(ctx, _contribs, offx, op):
					if debug_spin: print("[Guard] Blocked destroy_and_gain_fraction at ", offx)
					continue
				var numer: int = int((cmd as Dictionary).get("gain_numer", 1))
				var denom: int = max(1, int((cmd as Dictionary).get("gain_denom", 2)))
				var target_c: Dictionary = _find_contrib_by_offset(_contribs, offx)
				var gain_amt := 0
				if target_c is Dictionary and not (target_c as Dictionary).is_empty():
					var v := _compute_value(target_c)
					gain_amt = int(floor(float(v) * float(numer) / float(denom)))
				# destroy target
				var empty_res2 := _load_empty_token()
				if empty_res2 != null and empty_res2 is Resource:
					_replace_token_at_offset(ctx, offx, (empty_res2 as Resource).resource_path, -1, false)
				# permanent to self
				if gain_amt != 0 and effect_source != null:
					_apply_permanent_add_inventory("self", 0, "", "", gain_amt, false, ctx, false)
				# optional replace
				var rpath := String((cmd as Dictionary).get("replace_path", ""))
				if rpath.strip_edges() != "":
					_replace_token_at_offset(ctx, offx, rpath, -1, false)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"reroll_same_rarity":
				var offy := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				var target_c2 := _find_contrib_by_offset(_contribs, offy)
				if target_c2.is_empty():
					continue
				var tgt = target_c2.get("token")
				if tgt == null or not tgt.has_method("get"):
					continue
				var rrar := String(tgt.get("rarity")).to_lower()
				var troot := String((cmd as Dictionary).get("tokens_root", loot_scan_root))
				var excludes: Variant = (cmd as Dictionary).get("exclude_names", [])
				var sets: Array[String] = _class_allowed_sets(ctx)
				var path_rr := _pick_random_same_rarity_path(troot, rrar, String(tgt.get("name")), excludes, sets)
				if path_rr.strip_edges() == "":
					continue
				_replace_token_at_offset(ctx, offy, path_rr, -1, false)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
            "replace_by_rarity_step":
                var offz := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
                var target_c3 := _find_contrib_by_offset(_contribs, offz)
                if target_c3.is_empty():
                    continue
                var tgt2 = target_c3.get("token")
                var src_r := String(tgt2.get("rarity")).to_lower()
                var idx := ["common","uncommon","rare","legendary"].find(src_r)
                if idx == -1:
                    continue
                var mode := String((cmd as Dictionary).get("mode", "demote")).to_lower()
                if mode == "promote":
                    idx = min(idx + 1, 3)
                else:
                    idx = max(idx - 1, 0)
                var rtarget: String = ["common","uncommon","rare","legendary"][idx]
                var troot2 := String((cmd as Dictionary).get("tokens_root", loot_scan_root))
                var p2 := _pick_random_by_rarity_path(troot2, rtarget)
                if p2.strip_edges() == "":
                    continue
                _replace_token_at_offset(ctx, offz, p2, -1, false)
                _resync_contribs_from_board(ctx, _contribs)
                _refresh_dynamic_passives(ctx, _contribs)
            "replace_by_rarity":
                var offz2 := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
                var target_c4 := _find_contrib_by_offset(_contribs, offz2)
                if target_c4.is_empty():
                    continue
                var tgt4 = target_c4.get("token")
                var src_r4 := String(tgt4.get("rarity")).to_lower()
                var idx4 := ["common","uncommon","rare","legendary"].find(src_r4)
                if idx4 == -1:
                    continue
                var mode4 := String((cmd as Dictionary).get("mode", "demote")).to_lower()
                if mode4 == "promote":
                    idx4 = min(idx4 + 1, 3)
                else:
                    idx4 = max(idx4 - 1, 0)
                var rtarget4: String = ["common","uncommon","rare","legendary"][idx4]
                var troot4 := String((cmd as Dictionary).get("tokens_root", loot_scan_root))
                var p4 := _pick_random_by_rarity_path(troot4, rtarget4)
                if p4.strip_edges() == "":
                    continue
                _replace_token_at_offset(ctx, offz2, p4, -1, false)
                _resync_contribs_from_board(ctx, _contribs)
                _refresh_dynamic_passives(ctx, _contribs)
			"destroy_random_triggered_by_rarity_and_gain":
				var rar := String((cmd as Dictionary).get("rarity", "")).strip_edges().to_lower()
				var match_any := bool((cmd as Dictionary).get("match_any_rarity", rar == ""))
				var gain_self := bool((cmd as Dictionary).get("gain_to_self", true))
				var cands: Array[Dictionary] = []
				for c in _contribs:
					if not (c is Dictionary):
						continue
					var tok = (c as Dictionary).get("token")
					if tok == null or not (tok as Object).has_method("get"):
						continue
					if effect_source != null and tok == effect_source:
						continue
					var tok_rarity := String(tok.get("rarity")).strip_edges().to_lower()
					if not match_any and tok_rarity != rar:
						continue
					var meta_val = (c as Dictionary).get("meta")
					var final_val := 0
					if meta_val is Dictionary and (meta_val as Dictionary).has("final"):
						final_val = int((meta_val as Dictionary).get("final", 0))
					else:
						final_val = _compute_value(c)
					if gain_self and final_val <= 0:
						continue
					cands.append({"contrib": c, "final": final_val, "token": tok})
				if cands.is_empty():
					continue
				var pick := cands[_loot_rng.randi_range(0, cands.size()-1)]
				var pickc = pick.get("contrib", {})
				if not (pickc is Dictionary) or (pickc as Dictionary).is_empty():
					continue
				var offp := int((pickc as Dictionary).get("offset", 0))
				if _guard_blocks(ctx, _contribs, offp, op):
					continue
				var gain_amount := int(pick.get("final", _compute_value(pickc)))
				if gain_self and gain_amount <= 0:
					continue
				var empty_res5 := _load_empty_token()
				if empty_res5 is Resource:
					var destroyed_token = pick.get("token", null)
					if destroyed_token == null:
						destroyed_token = (pickc as Dictionary).get("token")
					_replace_token_at_offset(ctx, offp, (empty_res5 as Resource).resource_path, -1, false, destroyed_token)
				if gain_self and effect_source != null:
					_apply_permanent_add_inventory("self", 0, "", "", gain_amount, false, ctx, false)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"mastermind_destroy_target_and_buff":
				var offm := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				var target_cm := _find_contrib_by_offset(_contribs, offm)
				if target_cm.is_empty():
					continue
				var target_token = target_cm.get("token")
				if target_token == null:
					continue
				var destroyed_value := _compute_value(target_cm)
				var empty_pathm := String(empty_token_path).strip_edges()
				if empty_pathm == "":
					var empty_resm := _load_empty_token()
					if empty_resm is Resource:
						empty_pathm = String((empty_resm as Resource).resource_path)
				if empty_pathm == "":
					continue
				_replace_token_at_offset(ctx, offm, empty_pathm, -1, false, target_token)
				var offsets_to_buff: Array[int] = []
				for cc in _contribs:
					if cc is Dictionary:
						var offcc := int((cc as Dictionary).get("offset", 0))
						if offcc != offm:
							offsets_to_buff.append(offcc)
				for offcc in offsets_to_buff:
					_apply_permanent_add_inventory("offset", offcc, "", "", destroyed_value, false, ctx, false)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"destroy_all_copies_choose":
				var offc := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				var target_cc := _find_contrib_by_offset(_contribs, offc)
				if target_cc.is_empty():
					continue
				var nm3 := _token_name(target_cc.get("token"))
				var arrc := _get_inventory_array()
				var empty_resc := _load_empty_token()
				if empty_resc is Resource:
					for i in range(arrc.size()):
						var itc = arrc[i]
						if itc != null and (itc as Object).has_method("get") and _token_name(itc) == nm3:
							arrc[i] = (empty_resc as Resource).duplicate(true)
					_set_inventory_array(arrc)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"set_perm_to_self_current":
				var off_t := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				var self_c := _find_self_contrib(_contribs, effect_source)
				var target_c4 := _find_contrib_by_offset(_contribs, off_t)
				if self_c.is_empty() or target_c4.is_empty():
					continue
				var self_val := _compute_value(self_c)
				var tgt_val := _compute_value(target_c4)
				var delta := self_val - tgt_val
				if delta != 0:
					_apply_permanent_add_inventory("offset", off_t, "", "", delta, false, ctx, false)
					_refresh_all_slot_token_values(ctx)
					var had_force_offsets := false
					var prev_force_offsets = null
					if ctx is Dictionary:
						had_force_offsets = ctx.has("__force_value_sync_offsets")
						if had_force_offsets:
							prev_force_offsets = ctx["__force_value_sync_offsets"]
						var force_list: Array = []
						force_list.append(off_t)
						ctx["__force_value_sync_offsets"] = force_list
					_resync_contribs_from_board(ctx, _contribs)
					if ctx is Dictionary:
						if had_force_offsets:
							ctx["__force_value_sync_offsets"] = prev_force_offsets
						else:
							ctx.erase("__force_value_sync_offsets")
					_refresh_dynamic_passives(ctx, _contribs)
					var updated_target := _find_contrib_by_offset(_contribs, off_t)
					if updated_target is Dictionary:
						var sync_token = updated_target.get("token")
						var final_val := _compute_value(updated_target)
						if sync_token != null and (sync_token as Object).has_method("get"):
							var tv = sync_token.get("value")
							if tv != null:
								final_val = int(tv)
						updated_target["base"] = final_val
						updated_target["delta"] = 0
						updated_target["mult"] = 1.0
						if updated_target.has("meta") and typeof(updated_target["meta"]) == TYPE_DICTIONARY:
							var meta_sync: Dictionary = updated_target["meta"]
							meta_sync["final"] = final_val
							updated_target["meta"] = meta_sync
				else:
					_resync_contribs_from_board(ctx, _contribs)
					_refresh_dynamic_passives(ctx, _contribs)

			"set_self_perm_to_target_current":
				var off_t2 := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				var self_c2 := _find_self_contrib(_contribs, effect_source)
				var target_c5 := _find_contrib_by_offset(_contribs, off_t2)
				if self_c2.is_empty() or target_c5.is_empty():
					continue
				var self_val2 := _compute_value(self_c2)
				var tgt_val2 := _compute_value(target_c5)
				var delta2 := tgt_val2 - self_val2
				if delta2 != 0:
					_apply_permanent_add_inventory("self", 0, "", "", delta2, false, ctx, false)
					_refresh_all_slot_token_values(ctx)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"double_target_permanent":
				var offd2 := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				var target_c6 := _find_contrib_by_offset(_contribs, offd2)
				if target_c6.is_empty():
					continue
				var valc := _compute_value(target_c6)
				_apply_permanent_add_inventory("offset", offd2, "", "", valc, false, ctx, false)
				_refresh_all_slot_token_values(ctx)
				_resync_contribs_from_board(ctx, _contribs)
				_refresh_dynamic_passives(ctx, _contribs)
			"restart_round":
				_restart_current_round()
			"guarantee_next_loot_rarity":
				var rare := String((cmd as Dictionary).get("rarity", "")).strip_edges().to_lower()
				if rare != "":
					var cnt = max(1, int((cmd as Dictionary).get("count", 1)))
					var prev := int(_next_loot_guarantees.get(rare, 0))
					if cnt > prev:
						_next_loot_guarantees[rare] = cnt
			"add_loot_options_bonus":
				_loot_options_bonus += int((cmd as Dictionary).get("amount", 1))
			_:
				if debug_spin:
					print("[Commands] Unknown op: ", op)

		_current_effect_source = prev_effect_source
	await _drain_passive_refresh_queue(ctx, _contribs)
func _resync_contribs_from_board(ctx: Dictionary, contribs: Array) -> void:
	if contribs == null or not (contribs is Array):
		return
	for i in range(contribs.size()):
		var entry = contribs[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var contrib: Dictionary = entry
		var offset_val := int(contrib.get("offset", 999))
		var prev_base := int(contrib.get("base", 0))
		var prev_delta := int(contrib.get("delta", 0))
		var prev_mult := float(contrib.get("mult", 1.0))
		var prev_total := _compute_value(contrib)

		var slot: Control = null
		if ctx != null:
			slot = _slot_from_ctx(ctx, offset_val)
		var slot_token = null
		if slot != null and slot.has_meta("token_data"):
			slot_token = slot.get_meta("token_data")

		var prev_token = contrib.get("token")
		var token = slot_token if slot_token != null else prev_token
		if token == null:
			continue
		var token_changed: bool = prev_token != token
		contrib["token"] = token
		if token_changed:
			_queue_pending_passive_refresh(ctx, offset_val)
			for neighbor_offset in [offset_val - 1, offset_val + 1]:
				if abs(neighbor_offset) <= 2:
					_queue_pending_passive_refresh(ctx, neighbor_offset)
			contrib["delta"] = 0
			contrib["mult"] = 1.0
			contrib["steps"] = []
			_reset_temp_meta(token)

		if token != null and (token as Object).has_method("get"):
			var val = token.get("value")
			if val != null:
				contrib["base"] = max(int(val), 0)
			var rarity_val = token.get("rarity")
			if rarity_val != null and contrib.has("meta") and typeof(contrib["meta"]) == TYPE_DICTIONARY:
				contrib["meta"]["rarity"] = rarity_val

		if contrib.has("meta") and typeof(contrib["meta"]) == TYPE_DICTIONARY:
			var meta = contrib["meta"]
			meta["description"] = _get_token_description(token, String(contrib.get("kind", "")))
			contrib["meta"] = meta

		var new_total := _compute_value(contrib)
		var show_full_sync := false
		if ctx != null:
			var force_variant = ctx.get("__force_value_sync_offsets", null)
			if force_variant is Array:
				show_full_sync = (force_variant as Array).has(offset_val)
		if token_changed or new_total != prev_total:
			var steps_arr: Array = []
			if contrib.has("steps") and typeof(contrib["steps"]) == TYPE_ARRAY:
				steps_arr = contrib["steps"]
			var before_info := {"base": prev_base, "delta": prev_delta, "mult": prev_mult, "val": prev_total}
			var after_info := {"base": int(contrib.get("base", 0)), "delta": int(contrib.get("delta", 0)), "mult": float(contrib.get("mult", 1.0)), "val": new_total}
			var delta_val := new_total - prev_total
			var mult_change := float(contrib.get("mult", 1.0))
			if prev_mult != 0.0:
				mult_change = mult_change / prev_mult
			var step_kind := "replace" if token_changed else "value_sync"
			var step_source := "command:%s" % ("replace" if token_changed else "value_sync")
			var step_desc := "Token replaced" if token_changed else "Value adjusted"
			var step_log := {
				"source": step_source,
				"kind": step_kind,
				"desc": step_desc,
				"before": before_info,
				"after": after_info,
				"add_applied": delta_val,
				"mult_applied": mult_change
			}
			steps_arr.append(step_log)
			contrib["steps"] = steps_arr
			if ctx != null:
				var from_val := prev_total
				if token_changed or show_full_sync:
					from_val = 0
				var prev_override: Variant = null
				if not token_changed and from_val != prev_total:
					prev_override = prev_total
				_play_counting_popup(ctx, contrib, from_val, new_total, token_changed, step_log, prev_override)
			_invoke_on_value_changed(ctx, null, contrib, prev_total, new_total, step_log)
			if true:
				# Emit signals so listeners (e.g., tooltip highlighter) can refresh mid-spin
				emit_signal("token_step_applied", i, int(contrib.get("offset", 0)), step_log, new_total, contrib)
				emit_signal("token_value_shown", i, int(contrib.get("offset", 0)), new_total, contrib)

func _ability_should_refresh(ab) -> bool:
	if ab == null:
		return false
	if (ab as Object).has_method("should_refresh_after_board_change"):
		return bool(ab.call("should_refresh_after_board_change"))
	return false

func _find_refresh_logs_for_ability(contrib: Dictionary, ability) -> Array:
	var out: Array = []
	if contrib == null:
		return out
	var steps_variant: Variant = contrib.get("steps", [])
	if not (steps_variant is Array):
		return out
	for idx in range((steps_variant as Array).size()):
		var log: Variant = (steps_variant as Array)[idx]
		if not (log is Dictionary):
			continue
		if log.get("ability_ref") == ability:
			out.append({"index": idx, "log": log})
	return out

func _value_from_components(base: int, delta: int, mult: float) -> int:
	var sum_val: int = max(base + delta, 0)
	var mult_val: float = max(mult, 0.0)
	return max(int(floor(sum_val * mult_val)), 0)

func _set_contrib_final_value(contrib: Dictionary, target_value: int) -> int:
	target_value = max(target_value, 0)
	var base_val := int(contrib.get("base", 0))
	var mult_val := float(contrib.get("mult", 1.0))
	var original_delta := int(contrib.get("delta", 0))
	if mult_val <= 0.0:
		if target_value > 0:
			target_value = 0
		return _compute_value(contrib)
	var approx_delta := int(round(float(target_value) / mult_val)) - base_val
	var best_delta := approx_delta
	var best_value: int = _value_from_components(base_val, best_delta, mult_val)
	var best_diff: int = abs(best_value - target_value)
	for candidate in [original_delta, approx_delta]:
		var value: int = _value_from_components(base_val, candidate, mult_val)
		var diff: int = abs(value - target_value)
		if diff < best_diff:
			best_diff = diff
			best_delta = candidate
			best_value = value
	var visited: Dictionary = {}
	visited[best_delta] = true
	visited[original_delta] = true
	var to_visit: Array = [best_delta - 1, best_delta + 1, original_delta - 1, original_delta + 1]
	var guard := 0
	while to_visit.size() > 0 and guard < 128 and best_diff != 0:
		var candidate = to_visit.pop_back()
		if visited.has(candidate):
			continue
		visited[candidate] = true
		var value: int = _value_from_components(base_val, candidate, mult_val)
		var diff: int = abs(value - target_value)
		if diff < best_diff:
			best_diff = diff
			best_delta = candidate
			best_value = value
			if diff == 0:
				break
		if diff <= best_diff + 1:
			to_visit.append(candidate - 1)
			to_visit.append(candidate + 1)
		guard += 1
	contrib["delta"] = best_delta
	return best_value

func _update_log_effect(contrib: Dictionary, log_info: Dictionary, step_data: Dictionary) -> bool:
	var log_variant: Variant = log_info.get("log", {})
	var log: Dictionary = log_variant if log_variant is Dictionary else {}
	var kind := String(step_data.get("kind", ""))
	if kind == "":
		return false
	var ability_ref: Variant = step_data.get("_ability_ref", log.get("ability_ref"))
	log["ability_ref"] = ability_ref
	log["source"] = step_data.get("source", log.get("source", "unknown"))
	log["desc"] = step_data.get("desc", log.get("desc", ""))
	var base := int(contrib.get("base", 0))
	var changed := false
	if kind == "mult":
		var old_factor := float(log.get("mult_applied", 1.0))
		var new_factor: float = max(float(step_data.get("factor", 1.0)), 0.0)
		if abs(old_factor - new_factor) < 0.0001:
			return false
		var current_mult := float(contrib.get("mult", 1.0))
		var before_mult: float = current_mult
		if abs(old_factor) > 0.00001:
			before_mult = current_mult / old_factor
		var delta := int(contrib.get("delta", 0))
		var before_state := {
			"base": base,
			"delta": delta,
			"mult": before_mult,
			"val": _value_from_components(base, delta, before_mult)
		}
		var after_mult: float = before_mult * new_factor
		contrib["mult"] = after_mult
		var after_state := {
			"base": base,
			"delta": delta,
			"mult": after_mult,
			"val": _value_from_components(base, delta, after_mult)
		}
		log["before"] = before_state
		log["after"] = after_state
		log["mult_applied"] = new_factor
		log["add_applied"] = int(log.get("add_applied", 0))
		changed = true
	elif kind == "add":
		var old_amount := int(log.get("add_applied", 0))
		var new_amount := int(step_data.get("amount", 0))
		if old_amount == new_amount:
			return false
		var current_delta := int(contrib.get("delta", 0)) - old_amount
		var mult_val := float(contrib.get("mult", 1.0))
		var before_state := {
			"base": base,
			"delta": current_delta,
			"mult": mult_val,
			"val": _value_from_components(base, current_delta, mult_val)
		}
		var new_delta := current_delta + new_amount
		contrib["delta"] = new_delta
		var after_state := {
			"base": base,
			"delta": new_delta,
			"mult": mult_val,
			"val": _value_from_components(base, new_delta, mult_val)
		}
		log["before"] = before_state
		log["after"] = after_state
		log["add_applied"] = new_amount
		changed = true
	else:
		return false
	log_info["log"] = log
	_update_token_temp_meta_from_contrib(contrib.get("token"), contrib, kind == "add" or kind == "mult")
	return changed

func _remove_log_effect(contrib: Dictionary, log: Dictionary) -> bool:
	if log == null:
		return false
	var kind := String(log.get("kind", ""))
	if kind == "mult":
		var factor := float(log.get("mult_applied", 1.0))
		if abs(factor) < 0.00001:
			return false
		contrib["mult"] = float(contrib.get("mult", 1.0)) / factor
		_update_token_temp_meta_from_contrib(contrib.get("token"), contrib, true)
		return true
	elif kind == "add" or kind == "value_sync":
		var amount := int(log.get("add_applied", 0))
		if amount == 0:
			return false
		# For value_sync, we only log; do not invert base changes here.
		if kind == "add":
			contrib["delta"] = int(contrib.get("delta", 0)) - amount
		_update_token_temp_meta_from_contrib(contrib.get("token"), contrib, kind == "add")
		return true
	elif kind == "final_add":
		var before_state = log.get("before", {})
		if before_state is Dictionary and before_state.has("val"):
			_set_contrib_final_value(contrib, int(before_state.get("val", _compute_value(contrib))))
			_update_token_temp_meta_from_contrib(contrib.get("token"), contrib, false)
			return true
		var final_applied := int(log.get("final_applied", 0))
		if final_applied != 0:
			var target: int = max(_compute_value(contrib) - final_applied, 0)
			_set_contrib_final_value(contrib, target)
			_update_token_temp_meta_from_contrib(contrib.get("token"), contrib, false)
			return true
		return false
	return false

func _refresh_contrib_log_with_steps(contrib: Dictionary, ability, existing: Array, new_steps_raw: Array) -> bool:
	var steps_variant: Variant = contrib.get("steps", [])
	if not (steps_variant is Array):
		return false
	var steps: Array = steps_variant as Array
	var normalized: Array = []
	for step in new_steps_raw:
		if typeof(step) != TYPE_DICTIONARY:
			continue
		var step_norm := _normalize_step(step)
		step_norm["_ability_ref"] = ability
		normalized.append(step_norm)
	var changed := false
	if normalized.is_empty():
		for i in range(existing.size() - 1, -1, -1):
			var info: Dictionary = existing[i]
			var idx = int(info.get("index", -1))
			if idx < 0 or idx >= steps.size():
				continue
			var log_variant: Variant = info.get("log", {})
			var log: Dictionary = log_variant if log_variant is Dictionary else {}
			if _remove_log_effect(contrib, log):
				changed = true
			steps.remove_at(idx)
		contrib["steps"] = steps
		return changed
	var limit: int = min(existing.size(), normalized.size())
	for i in range(limit):
		var info: Dictionary = existing[i]
		var idx = int(info.get("index", -1))
		if idx < 0 or idx >= steps.size():
			continue
		if _update_log_effect(contrib, info, normalized[i]):
			changed = true
		steps[idx] = info.get("log", steps[idx])
	if existing.size() > normalized.size():
		for i in range(existing.size() - 1, normalized.size() - 1, -1):
			var info: Dictionary = existing[i]
			var idx = int(info.get("index", -1))
			if idx < 0 or idx >= steps.size():
				continue
			var log_variant: Variant = info.get("log", {})
			var log: Dictionary = log_variant if log_variant is Dictionary else {}
			if _remove_log_effect(contrib, log):
				changed = true
			steps.remove_at(idx)
	# If there are more new steps than existing logs, append them and apply to contrib.
	if normalized.size() > existing.size():
		for i in range(existing.size(), normalized.size()):
			var s: Dictionary = normalized[i]
			_apply_step(contrib, s)
			changed = true
		# steps were appended by _apply_step; refresh local steps var
		steps = contrib.get("steps", steps)
		if not (steps is Array):
			steps = []
	contrib["steps"] = steps
	return changed

func _update_slot_value(ctx: Dictionary, contrib: Dictionary, value: int) -> void:
	if ctx == null or not (ctx is Dictionary):
		return
	var slot := _slot_from_ctx(ctx, int(contrib.get("offset", 0)))
	if slot == null:
		return
	var si := slot.get_node_or_null("slotItem")
	if si != null and si.has_method("set_value"):
		si.call_deferred("set_value", value)

func _refresh_dynamic_passives(ctx: Variant, contribs: Array) -> void:
	if contribs == null or not (contribs is Array):
		return
	var ctx_dict: Dictionary = {}
	if ctx is Dictionary:
		ctx_dict = ctx as Dictionary

	# Build an updated 5-slot view for abilities that depend on winner/neighbors.
	# neighbors order: [-2, -1, 1, 2]
	var view_ctx: Dictionary = ctx_dict.duplicate(true)
	var by_offset: Dictionary = {}
	for entry in contribs:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var c2: Dictionary = entry
		by_offset[int(c2.get("offset", 999))] = c2.get("token")
	if by_offset.has(0):
		view_ctx["winner"] = by_offset.get(0)
	var neighs: Array = []
	for off in [-2, -1, 1, 2]:
		neighs.append(by_offset.get(off))
	view_ctx["neighbors"] = neighs

	for entry in contribs:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var contrib: Dictionary = entry
		var token = contrib.get("token")
		if token == null or not token.has_method("get"):
			continue
		var abilities = token.get("abilities")
		if not (abilities is Array):
			continue
		var updated := false
		for ab in abilities:
			if ab == null:
				continue
			if not _ability_is_active_during_spin(ab):
				continue
			if not _ability_should_refresh(ab):
				continue
			var logs := _find_refresh_logs_for_ability(contrib, ab)
			var matches: bool = ab.matches_target(view_ctx, contrib, token)
			var new_steps: Array = []
			if (ab as Object).has_method("build_steps"):
				if matches:
					new_steps = ab.build_steps(view_ctx, contrib, token)
				else:
					new_steps = []
			# If there are no existing logs but the ability now matches, add new steps.
			if logs.is_empty() and matches and not new_steps.is_empty():
				for step in new_steps:
					if typeof(step) != TYPE_DICTIONARY:
						continue
					var step_norm := _normalize_step(step)
					step_norm["_ability_ref"] = ab
					_apply_step(contrib, step_norm)
				updated = true
			else:
				if _refresh_contrib_log_with_steps(contrib, ab, logs, new_steps):
					updated = true
		if updated:
			var new_val := _compute_value(contrib)
			_update_slot_value(ctx_dict, contrib, new_val)

func _resolve_inventory_owner_node() -> Node:
	var owner := get_node_or_null(inventory_owner_path)
	if owner != null:
		return owner
	# Fallback: try to find spinRoot in the current scene
	var scene := get_tree().current_scene
	if scene != null:
		var sr := scene.find_child("spinRoot", true, false)
		if sr != null and sr is Node:
			return sr
	return null

func _replace_token_at_offset(ctx: Dictionary, offset: int, token_path: String, set_value: int, preserve_tags: bool, target_token_override = null, source_token_ref = null) -> Resource:
	var trimmed_path := String(token_path).strip_edges()
	var has_path := trimmed_path != ""
	token_path = trimmed_path
	if not has_path and source_token_ref == null:
		return null
	var slot := _slot_from_ctx(ctx, offset)
	if slot != null:
		_shake_slot(slot)
	var target_token = target_token_override
	if target_token == null and slot != null:
		if slot.has_meta("token_data"):
			target_token = slot.get_meta("token_data")

	var removing_empty := false
	if target_token != null:
		removing_empty = _is_empty_token(target_token) and _token_path_is_empty(token_path)

	# If we have a token to remove, let its abilities react (e.g., on-removed penalties)
	if target_token != null:
		# Record destroyer on ctx for on_removed hooks
		if ctx is Dictionary:
			ctx["destroyed_by_token"] = _current_effect_source
		var removed_cmds := _collect_on_removed_commands(ctx, target_token)
		if removed_cmds is Array and not removed_cmds.is_empty():
			_execute_ability_commands(removed_cmds, ctx, [], target_token)
		_notify_any_token_destroyed(ctx, target_token, "replace_at_offset")

	var owner := _resolve_inventory_owner_node()
	if owner == null:
		if debug_spin:
			print("[Commands] No inventory owner found; skip replace_at_offset")
		return null
	var prop := String(inventory_property)
	if prop.strip_edges() == "":
		prop = "items"  # default to spinRoot.items
	if not owner.has_method("get"):
		return null
	var arr = owner.get(prop)
	if typeof(arr) != TYPE_ARRAY:
		# Fallbacks: try common inventory properties
		var arr_items = owner.get("items")
		if typeof(arr_items) == TYPE_ARRAY:
			prop = "items"
			arr = arr_items
		else:
			var arr_tokens = owner.get("tokens")
			if typeof(arr_tokens) == TYPE_ARRAY:
				prop = "tokens"
				arr = arr_tokens
			else:
				return null

	# Find index by identity if possible
	var idx := -1
	for i in range((arr as Array).size()):
		if (arr as Array)[i] == target_token:
			idx = i
			break
	if idx < 0 and target_token is Resource:
		# Fallback: attempt to match by resource_path and name
		for i in range((arr as Array).size()):
			var it = (arr as Array)[i]
			if it is Resource and (it as Resource).resource_path != "" and (it as Resource).resource_path == (target_token as Resource).resource_path:
				idx = i
				break
	if idx < 0:
		if debug_spin:
			print("[Commands] Could not locate target token in inventory for offset ", offset)
		return null

	if removing_empty:
		(arr as Array).remove_at(idx)
		owner.set(prop, arr)
		if owner.has_method("_update_inventory_strip"):
			owner.call_deferred("_update_inventory_strip")
		if owner.has_method("_refresh_inventory_baseline"):
			owner.call_deferred("_refresh_inventory_baseline")
		if ctx != null and ctx is Dictionary:
			var ctx_dict: Dictionary = ctx
			ctx_dict["board_tokens"] = _get_inventory_array()
			if abs(offset) <= 2 and offset != 0 and ctx_dict.has("spin_root"):
				var sr = ctx_dict["spin_root"]
				if sr != null:
					if (sr as Object).has_method("handle_triggered_empty_removed"):
						sr.call("handle_triggered_empty_removed", offset)
					if (sr as Object).has_method("_build_slot_map"):
						var updated_map = sr.call("_build_slot_map")
						if typeof(updated_map) == TYPE_DICTIONARY:
							ctx_dict["slot_map"] = updated_map
					if (sr as Object).has_method("_gather_neighbor_tokens") and (sr as Object).has_method("get"):
						var win_idx_var = sr.get("_last_winning_slot_idx")
						if typeof(win_idx_var) == TYPE_INT:
							var fresh_neighbors = sr.call("_gather_neighbor_tokens", int(win_idx_var))
							ctx_dict["neighbors"] = fresh_neighbors
		return null

	var rep: Resource = null
	if has_path:
		rep = ResourceLoader.load(trimmed_path)
		if rep == null or not (rep is Resource):
			return null
	elif source_token_ref is Resource:
		rep = source_token_ref
	else:
		return null
	var inst: Resource = (rep as Resource).duplicate(true)
	_init_token_base_value(inst)
	_ensure_token_uid(inst)
	_reset_temp_meta(inst)
	# Optional: set incoming value and preserve tags
	if inst.has_method("set") and set_value >= 0:
		var clamped: int = max(1, int(set_value))
		inst.set("value", clamped)
		if inst.has_method("set_meta"):
			inst.set_meta("base_value", clamped)
		_init_token_base_value(inst)
	if preserve_tags:
		var src_tags: Variant = null
		if target_token != null and (target_token as Object).has_method("get"):
			src_tags = target_token.get("tags")
		if src_tags is Array and inst.has_method("set"):
			inst.set("tags", PackedStringArray(src_tags))

	(arr as Array)[idx] = inst
	owner.set(prop, arr)

	if slot != null:
		_apply_token_to_slot(slot, inst)

	# Try to refresh inventory strip visuals if available
	if owner.has_method("_update_inventory_strip"):
		owner.call_deferred("_update_inventory_strip")

	if ctx != null and ctx is Dictionary:
		ctx["board_tokens"] = _get_inventory_array()

	_register_effect_target_current(inst)

	return inst
func _find_contrib_by_offset(contribs: Array, off: int) -> Dictionary:
	for c in contribs:
		if c is Dictionary and int((c as Dictionary).get("offset", 999)) == int(off):
			return c
	return {}

func _find_self_contrib(contribs: Array, source_token) -> Dictionary:
	for c in contribs:
		if c is Dictionary and c.get("token") == source_token:
			return c
	return {}

func _op_needs_offset(op: String) -> bool:
    match op:
        "replace_at_offset", "destroy", "destroy_and_gain_fraction", "reroll_same_rarity", "replace_by_rarity_step", "replace_by_rarity", "set_perm_to_self_current", "set_self_perm_to_target_current", "permanent_add", "double_target_permanent", "replace_target_with_self_copy", "replace_at_offset_from_choices", "copy_target_to_inventory":
            return true
        _:
            return false

func _prompt_target_offset(ctx: Dictionary, exclude_center: bool = true, ordinal: int = 1) -> int:
	if ctx != null and ctx.has("spin_root"):
		var sr = ctx["spin_root"]
		if sr != null and (sr as Object).has_method("choose_target_offset"):
			return await sr.call("choose_target_offset", exclude_center, ordinal)
	# Fallback: prefer first neighbor to the right
	return 1

func _pick_random_same_rarity_path(tokens_root: String, rarity: String, exclude_name: String, excludes: Variant, allowed_sets: Array[String] = []) -> String:
	var out: Array[String] = []
	var all_paths: Array[String] = _collect_token_paths_under(tokens_root)
	for p in all_paths:
		var res = ResourceLoader.load(p)
		if res == null or not (res as Object).has_method("get"):
			continue
		var nm = String(res.get("name"))
		if nm == exclude_name:
			continue
		if excludes is Array and (excludes as Array).has(nm):
			continue
		if String(res.get("rarity")).to_lower() == rarity:
			if not allowed_sets.is_empty():
				var tags = res.get("tags") if (res as Object).has_method("get") else []
				var ok := false
				if tags is Array:
					for t in tags:
						if typeof(t) == TYPE_STRING and allowed_sets.has(String(t)):
							ok = true
							break
				if not ok:
					continue
			out.append(p)
	if out.is_empty():
		return ""
	_loot_rng.randomize()
	_initialize_artifact_library()
	return out[_loot_rng.randi_range(0, out.size()-1)]

func _pick_random_by_rarity_path(tokens_root: String, rarity: String) -> String:
	var out: Array[String] = []
	var all_paths: Array[String] = _collect_token_paths_under(tokens_root)
	for p in all_paths:
		var res = ResourceLoader.load(p)
		if res == null or not (res as Object).has_method("get"):
			continue
		if String(res.get("rarity")).to_lower() == rarity:
			out.append(p)
	if out.is_empty():
		return ""
	_loot_rng.randomize()
	_initialize_artifact_library()
	return out[_loot_rng.randi_range(0, out.size()-1)]

func _collect_token_paths_under(root: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return paths
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			if name.begins_with("."):
				continue
			paths.append_array(_collect_token_paths_under(root.path_join(name)))
		else:
			if name.ends_with(".tres") or name.ends_with(".res"):
				paths.append(root.path_join(name))
	dir.list_dir_end()
	return paths

func _class_allowed_sets(ctx: Dictionary) -> Array[String]:
	if ctx == null:
		return []
	var cd = ctx.get("class_data") if ctx.has("class_data") else null
	if cd != null and (cd as Object).has_method("get"):
		var sets_prop = cd.get("sets")
		if sets_prop is Array:
			var out: Array[String] = []
			for s in sets_prop:
				if typeof(s) == TYPE_STRING:
					out.append(String(s))
			return out
	return []

func _apply_treasure_hoard_spawn() -> void:
	var arr := _get_inventory_array()
	var hoards := 0
	for t in arr:
		if t != null and (t as Object).has_method("get") and String(t.get("name")) == "Treasure Hoard":
			hoards += 1
	if hoards <= 0:
		return
	var chest_paths: Array[String] = ["res://tokens/TreasureHunters/smallChest.tres", "res://tokens/TreasureHunters/goldenChest.tres"]
	for i in range(hoards):
		var p := chest_paths[_loot_rng.randi_range(0, chest_paths.size()-1)]
		var res := ResourceLoader.load(p)
		if res is Resource:
			var dup := (res as Resource).duplicate(true)
			_init_token_base_value(dup)
			var inv := _get_inventory_array()
			var idx := _find_empty_index(inv)
			if idx >= 0:
				inv[idx] = dup
			else:
				inv.append(dup)
			_set_inventory_array(inv)

func _register_guard_offset(ctx: Dictionary, off: int) -> void:
	if ctx == null:
		return
	var arr: Array = ctx.get("guarded_offsets", [])
	if not (arr is Array):
		arr = []
	(arr as Array).append(off)
	ctx["guarded_offsets"] = arr

func _register_value_guard(ctx: Dictionary, source_off: int, min_threshold: int, triggered_only: bool) -> void:
	if ctx == null:
		return
	var arr: Array = ctx.get("value_guards", [])
	if not (arr is Array):
		arr = []
	(arr as Array).append({"source_offset": source_off, "threshold": min_threshold, "triggered_only": bool(triggered_only)})
	ctx["value_guards"] = arr

func _guard_blocks(ctx: Dictionary, contribs: Array, target_off: int, op: String) -> bool:
	if ctx == null:
		return false
	var g = ctx.get("guarded_offsets", [])
	if g is Array and (g as Array).has(target_off):
		return true
	var vgs = ctx.get("value_guards", [])
	if vgs is Array:
		for vg in vgs:
			if not (vg is Dictionary):
				continue
			var thr := int((vg as Dictionary).get("threshold", 0))
			var trig_only := bool((vg as Dictionary).get("triggered_only", true))
			if trig_only and abs(target_off) == 0:
				continue
			var c := _find_contrib_by_offset(contribs, target_off)
			if c is Dictionary and not (c as Dictionary).is_empty():
				var val := _compute_value(c)
				if val < thr:
					return true
	return false

func _notify_any_token_destroyed(ctx: Dictionary, destroyed_token, cause: String = "") -> void:
    var arr := _get_inventory_array()
    # Track last destroyed for effects that may reference it later (e.g., Poacher)
    if ctx is Dictionary:
        ctx["last_destroyed_token"] = destroyed_token
        ctx["destroyed_token"] = destroyed_token
	var all_cmds: Array = []
	# Provide the destroyer token (if any) via context
	var killer = _current_effect_source
	if ctx is Dictionary:
		ctx["destroyed_by_token"] = killer
	for t in arr:
		if t == null or not (t as Object).has_method("get"):
			continue
		var abilities = t.get("abilities")
		if abilities is Array:
			for ab in abilities:
				if ab == null: continue
            		if (ab as Object).has_method("on_any_token_destroyed"):
            			var cmds = ab.call("on_any_token_destroyed", ctx, destroyed_token, t)
					if cmds is Array:
						for c in cmds:
							if typeof(c) == TYPE_DICTIONARY:
								all_cmds.append(c)
	if not all_cmds.is_empty():
		_execute_ability_commands(all_cmds, ctx, [], null)
	# Track opened chests total
	if destroyed_token != null and (destroyed_token as Object).has_method("get") and _token_has_tag(destroyed_token, "chest"):
		var k := "chests_opened_total"
		var val := int(ctx.get(k, 0)) + 1
		ctx[k] = val

func _restart_current_round() -> void:
	var spr: int = max(1, spins_per_round)
	var rounds_completed: int = int(max(spin_index - 1, 0) / spr)
	spin_index = rounds_completed * spr
	_update_spin_counters()
	_update_round_and_deadline_labels()

func _apply_token_to_slot(slot: Control, token: Resource) -> void:
	if slot == null or token == null:
		return
	# Update meta used everywhere
	var prev_token = null
	if slot.has_meta("token_data"):
		prev_token = slot.get_meta("token_data")
		if prev_token != null:
			_unregister_token_control(prev_token, slot)
	_ensure_token_uid(token)
	slot.set_meta("token_data", token)
	_register_token_control(token, slot)
	_register_effect_target_current(token)
	# Try preferred API: set exported `data` property on the root control
	var has_data_prop := false
	for p in slot.get_property_list():
		if String(p.get("name", "")) == "data":
			has_data_prop = true
			break
	if has_data_prop:
		slot.set("data", token)
		return
	# Fallback: if root exposes an _apply(data) method
	if slot.has_method("_apply"):
		slot.call("_apply", token)
		return
	# Final fallback: update a child named "slotItem" if present
	var si := slot.get_node_or_null("slotItem")
	if si != null and si.has_method("set"):
		si.set("data", token)

func _replace_board_tag_in_slotmap(ctx: Dictionary, target_tag: String, token_path: String) -> void:
	if token_path.strip_edges() == "":
		return
	var rep: Resource = ResourceLoader.load(token_path)
	if rep == null or not (rep is Resource):
		return
	var slots := _visible_slots_from_ctx(ctx)
	if slots.is_empty():
		return
	for slot in slots:
		if not (slot is Control):
			continue
		var tok = (slot as Control).get_meta("token_data") if (slot as Control).has_meta("token_data") else null
		if _token_has_tag(tok, target_tag):
			_shake_slot(slot as Control)
			var inst: Resource = (rep as Resource).duplicate(true)
			_init_token_base_value(inst)
			_apply_token_to_slot(slot as Control, inst)

func _update_slot_map_for_replacements(ctx: Dictionary, replacements: Array) -> void:
	if replacements.is_empty():
		return
	if ctx == null or not ctx.has("slot_map"):
		return
	var sm = ctx["slot_map"]
	if not (sm is Dictionary):
		return
	for key in (sm as Dictionary).keys():
		var slot = (sm as Dictionary).get(key)
		if not (slot is Control):
			continue
		var ctrl := slot as Control
		var slot_token = ctrl.get_meta("token_data") if ctrl.has_meta("token_data") else null
		for entry in replacements:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var old_token = entry.get("old")
			if slot_token != old_token:
				continue
			var new_token = entry.get("new")
			if new_token == null:
				continue
			_shake_slot(ctrl)
			_apply_token_to_slot(ctrl, new_token)
			break

func _replace_board_empties_in_slotmap(ctx: Dictionary, token_path: String) -> void:
	if token_path.strip_edges() == "":
		return
	var rep: Resource = ResourceLoader.load(token_path)
	if rep == null or not (rep is Resource):
		return
	var slots := _visible_slots_from_ctx(ctx)
	if slots.is_empty():
		return
	for slot in slots:
		if not (slot is Control):
			continue
		var tok = (slot as Control).get_meta("token_data") if (slot as Control).has_meta("token_data") else null
		if _is_empty_token(tok):
			_shake_slot(slot as Control)
			var inst: Resource = (rep as Resource).duplicate(true)
			_init_token_base_value(inst)
			_apply_token_to_slot(slot as Control, inst)

func _visible_slots_from_ctx(ctx: Dictionary) -> Array:
	if not ctx.has("slot_map"):
		return []
	var sm = ctx["slot_map"]
	if not (sm is Dictionary):
		return []
	# Grab any slot to find the HBox and its ScrollContainer
	var any_slot: Control = null
	for k in (sm as Dictionary).keys():
		var s = (sm as Dictionary).get(k)
		if s is Control:
			any_slot = s
			break
	if any_slot == null:
		return []
	var hbox := any_slot.get_parent()
	if hbox == null or not (hbox is Control):
		return []
	var sc: ScrollContainer = null
	var n := hbox.get_parent()
	while n != null and sc == null:
		if n is ScrollContainer:
			sc = n as ScrollContainer
			break
		n = n.get_parent()
	var left := 0.0
	var right := 1e12
	if sc != null:
		left = float(sc.scroll_horizontal)
		right = left + sc.size.x
	var out: Array = []
	for child in hbox.get_children():
		if child is Control:
			var c := child as Control
			var center_x: float = c.position.x + c.size.x * 0.5
			if center_x >= left and center_x <= right:
				out.append(c)
	return out

func _refresh_all_slot_token_values(ctx: Dictionary) -> void:
	# Re-initialize base values for all tokens currently displayed in slots,
	# so any new permanent offsets are applied to their displayed value.
	if ctx == null or not ctx.has("slot_map"):
		return
	var sm = ctx["slot_map"]
	if not (sm is Dictionary):
		return
	for k in (sm as Dictionary).keys():
		var slot = (sm as Dictionary).get(k)
		if not (slot is Control):
			continue
		var ctrl: Control = slot as Control
		var tok = ctrl.get_meta("token_data") if ctrl.has_meta("token_data") else null
		if tok == null:
			continue
		_init_token_base_value(tok)
		# Update inline slot value label if present
		var si := ctrl.get_node_or_null("slotItem")
		if si != null and si.has_method("set_value"):
			var vv := 0
			if (tok as Object).has_method("get"):
				var v = tok.get("value")
				if v != null:
					vv = int(v)
			si.call_deferred("set_value", vv)

func _shake_slot(slot: Control) -> void:
	if slot == null:
		return
	var base_mod := slot.modulate
	var fx := get_tree().create_tween()
	fx.tween_property(slot, "modulate", Color(base_mod.r, base_mod.g, base_mod.b, 0.90), 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fx.chain().tween_property(slot, "modulate", base_mod, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var shake_target: Node = slot.get_node_or_null("slotItem")
	if shake_target == null:
		shake_target = slot
	if not (shake_target is CanvasItem):
		return
	var rng := _mk_rng()
	var orig_pos: Vector2 = (shake_target as CanvasItem).position
	var shake := get_tree().create_tween()
	var shakes := 3
	var strength: float = 8.0
	for i in range(shakes):
		var offv := Vector2(rng.randf_range(-strength, strength), rng.randf_range(-strength, strength))
		shake.tween_property(shake_target, "position", orig_pos + offv, 0.03).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	shake.tween_property(shake_target, "position", orig_pos, 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _replace_all_empties_in_inventory(token_path: String, ctx: Variant = null) -> void:
	if token_path.strip_edges() == "":
		return
	var owner := _resolve_inventory_owner_node()
	if owner == null or not owner.has_method("get"):
		return
	var prop := String(inventory_property)
	if prop.strip_edges() == "":
		prop = "items"
	var arr = owner.get(prop)
	if typeof(arr) != TYPE_ARRAY:
		# Fallbacks: try common inventory properties
		var arr_items = owner.get("items")
		if typeof(arr_items) == TYPE_ARRAY:
			prop = "items"
			arr = arr_items
		else:
			var arr_tokens = owner.get("tokens")
			if typeof(arr_tokens) == TYPE_ARRAY:
				prop = "tokens"
				arr = arr_tokens
			else:
				return
	var rep: Resource = ResourceLoader.load(token_path)
	if rep == null or not (rep is Resource):
		return
	var changed := false
	for i in range((arr as Array).size()):
		var it = (arr as Array)[i]
		if _is_empty_token(it):
			var inst: Resource = (rep as Resource).duplicate(true)
			_init_token_base_value(inst)
			_ensure_token_uid(inst)
			(arr as Array)[i] = inst
			_register_effect_target_current(inst)
			changed = true
	if changed:
		owner.set(prop, arr)
		if owner.has_method("_update_inventory_strip"):
			owner.call_deferred("_update_inventory_strip")
		if ctx is Dictionary:
			var ctx_dict: Dictionary = ctx as Dictionary
			ctx_dict["board_tokens"] = _get_inventory_array()

func _apply_permanent_add_inventory(target_kind: String, target_offset: int, target_tag: String, target_name: String, amount: int, destroy_if_zero: bool, ctx: Dictionary, propagate_same_key: bool = false) -> void:
	var owner := _resolve_inventory_owner_node()
	if owner == null or not owner.has_method("get"):
		return
	var prop := String(inventory_property)
	if prop.strip_edges() == "":
		prop = "items"
	var arr = owner.get(prop)
	if typeof(arr) != TYPE_ARRAY:
		# Fallbacks: try common inventory properties
		var arr_items = owner.get("items")
		if typeof(arr_items) == TYPE_ARRAY:
			prop = "items"
			arr = arr_items
		else:
			var arr_tokens = owner.get("tokens")
			if typeof(arr_tokens) == TYPE_ARRAY:
				prop = "tokens"
				arr = arr_tokens
			else:
				return

	var kind_norm := String(target_kind).strip_edges().to_lower()
	if kind_norm == "choose":
		kind_norm = "offset"
	var tag_norm := String(target_tag).strip_edges().to_lower()
	var name_norm := String(target_name).strip_edges().to_lower()
	var use_tag_offsets := kind_norm == "tag" and tag_norm != ""
	var use_name_offsets := kind_norm == "name" and name_norm != ""
	var use_global_offsets := kind_norm == "any"

	if use_tag_offsets:
		_token_tag_offsets[tag_norm] = int(_token_tag_offsets.get(tag_norm, 0)) + amount
	elif use_name_offsets:
		_token_name_offsets[name_norm] = int(_token_name_offsets.get(name_norm, 0)) + amount
	elif use_global_offsets:
		_token_global_offset += amount

	# Only derive an anchor for self/offset targeting; tag/name/global should not use anchor-based propagation.
	var anchor_token = null
	var anchor_key := ""
	var allow_propagate_same_key := (kind_norm == "self" or kind_norm == "offset") and propagate_same_key
	if kind_norm == "self":
		if _current_effect_source is Resource:
			anchor_token = _current_effect_source
			anchor_key = _token_key(anchor_token)
		if anchor_token == null:
			var anchor_slot := _slot_from_ctx(ctx, target_offset)
			if anchor_slot != null and anchor_slot.has_meta("token_data"):
				anchor_token = anchor_slot.get_meta("token_data")
				anchor_key = _token_key(anchor_token)
	elif kind_norm == "offset":
		var anchor_slot := _slot_from_ctx(ctx, target_offset)
		if anchor_slot != null and anchor_slot.has_meta("token_data"):
			anchor_token = anchor_slot.get_meta("token_data")
			anchor_key = _token_key(anchor_token)

	var matches_token = func(tok) -> bool:
		if tok == null:
			return false
		match kind_norm:
			"self", "offset":
				if anchor_token != null:
					return tok == anchor_token
				return false
			"name":
				if name_norm != "":
					return _normalize_token_name(_token_name(tok)) == name_norm
				return false
			"tag":
				if tag_norm != "":
					return _token_has_tag(tok, target_tag)
				return false
			"any":
				return true
			_:
				return false

	var affected: Dictionary = {}
	var per_key_incremented: Dictionary = {}
	var list: Array = arr

	for i in range(list.size()):
		var tok = list[i]
		var matched: bool = bool(matches_token.call(tok))
		# Propagate by same-key only for self/offset modes when requested.
		if not matched and allow_propagate_same_key and anchor_key != "":
			matched = (_token_key(tok) == anchor_key)
		if matched:
			var key := _token_key(tok)
			affected[key] = true
			if not use_tag_offsets and not use_name_offsets and not use_global_offsets:
				if not per_key_incremented.has(key):
					var cur := int(_token_value_offsets.get(key, 0))
					_token_value_offsets[key] = cur + amount
					per_key_incremented[key] = true

	var changed := false
	var replaced_tokens: Array = []
	for i in range(list.size()):
		var tok = list[i]
		if tok == null:
			continue
		var key := _token_key(tok)
		if not affected.has(key):
			continue
		var orig_token = tok
		_init_token_base_value(tok)
		var curv := 0
		if tok != null and (tok as Object).has_method("get"):
			var vv2 = tok.get("value")
			if vv2 != null:
				curv = int(vv2)
		# Only destroy if temporary value (not base) drops below 1, or by explicit effect
		if destroy_if_zero and curv < 1:
			var empty_res := _load_empty_token()
			if empty_res is Resource:
				var inst := (empty_res as Resource).duplicate(true)
				_init_token_base_value(inst)
				_ensure_token_uid(inst)
				list[i] = inst
				replaced_tokens.append({"old": orig_token, "new": inst})
				_register_effect_target_current(inst)
				changed = true
				continue
		changed = true
		_ensure_token_uid(tok)
		_register_effect_target_current(tok)

	if changed:
		owner.set(prop, list)
		if owner.has_method("_update_inventory_strip"):
			owner.call_deferred("_update_inventory_strip")
		if ctx != null and ctx is Dictionary:
			ctx["board_tokens"] = _get_inventory_array()
			if not replaced_tokens.is_empty():
				_update_slot_map_for_replacements(ctx, replaced_tokens)
			# Note: do not auto-register unrelated tokens as highlight targets here.
			# Targets are registered individually when they are actually affected above.


func _queue_pending_passive_refresh(ctx, offset: int) -> void:
	if ctx == null:
		return
	if not (ctx is Dictionary):
		return
	var pending_var = ctx.get("__pending_passive_offsets", [])
	var list: Array = []
	if pending_var is Array:
		list = pending_var
	if not list.has(offset):
		list.append(offset)
	ctx["__pending_passive_offsets"] = list

func _find_contrib_index_by_offset(contribs: Array, offset: int) -> int:
	if contribs == null or not (contribs is Array):
		return -1
	for i in range(contribs.size()):
		var entry = contribs[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int((entry as Dictionary).get("offset", 999)) == offset:
			return i
	return -1

func _reapply_passives_for_offset(ctx: Dictionary, contribs: Array, offset: int) -> void:
	if ctx == null or not (ctx is Dictionary):
		return
	if contribs == null or not (contribs is Array):
		return
	var idx := _find_contrib_index_by_offset(contribs, offset)
	if idx < 0:
		return
	var contrib: Dictionary = contribs[idx]
	var token = contrib.get("token")
	if token == null or not token.has_method("get"):
		return
	var parts := _collect_ability_spin_steps(ctx, contrib, null)
	var immediate_var = parts.get("immediate", [])
	var immediate: Array = []
	if immediate_var is Array:
		immediate = (immediate_var as Array)
	if not immediate.is_empty():
		await _apply_steps_now(idx, contrib, immediate.duplicate(true), ctx, token)

func _drain_passive_refresh_queue(ctx: Dictionary, contribs: Array) -> void:
	if ctx == null or not (ctx is Dictionary):
		return
	if contribs == null or not (contribs is Array):
		ctx["__pending_passive_offsets"] = []
		return
	var guard: int = 0
	while guard < 16:
		guard += 1
		var pending_var = ctx.get("__pending_passive_offsets", [])
		if not (pending_var is Array):
			break
		var offsets: Array = (pending_var as Array).duplicate(true)
		if offsets.is_empty():
			ctx["__pending_passive_offsets"] = []
			break
		ctx["__pending_passive_offsets"] = []
		var seen: Dictionary = {}
		for off in offsets:
			var off_int := int(off)
			if seen.has(off_int):
				continue
			seen[off_int] = true
			await _reapply_passives_for_offset(ctx, contribs, off_int)
	if guard >= 16 and debug_spin:
		print("[Passives] Passive refresh guard limit reached; remaining=", ctx.get("__pending_passive_offsets", []))

func _destroy_inventory_coins(max_to_destroy: int, ctx: Dictionary) -> int:
	if max_to_destroy <= 0:
		return 0
	var owner := _resolve_inventory_owner_node()
	if owner == null or not owner.has_method("get"):
		return 0
	var prop := String(inventory_property)
	if prop.strip_edges() == "":
		prop = "items"
	var arr = owner.get(prop)
	if typeof(arr) != TYPE_ARRAY:
		var arr_items = owner.get("items")
		if typeof(arr_items) == TYPE_ARRAY:
			prop = "items"
			arr = arr_items
		else:
			var arr_tokens = owner.get("tokens")
			if typeof(arr_tokens) == TYPE_ARRAY:
				prop = "tokens"
				arr = arr_tokens
			else:
				return 0
	var empty_res := _load_empty_token()
	if empty_res == null or not (empty_res is Resource):
		return 0
	var destroyed := 0
	var replaced_tokens: Array = []
	for i in range((arr as Array).size()):
		if destroyed >= max_to_destroy:
			break
		var tok = (arr as Array)[i]
		if not _token_is_coin(tok):
			continue
		var inst: Resource = (empty_res as Resource).duplicate(true)
		_init_token_base_value(inst)
		_ensure_token_uid(inst)
		(arr as Array)[i] = inst
		replaced_tokens.append({"old": tok, "new": inst})
		_register_effect_target_current(inst)
		destroyed += 1
	if destroyed == 0:
		return 0
	owner.set(prop, arr)
	if owner.has_method("_update_inventory_strip"):
		owner.call_deferred("_update_inventory_strip")
	if ctx is Dictionary:
		ctx["board_tokens"] = _get_inventory_array()
		if not replaced_tokens.is_empty():
			_update_slot_map_for_replacements(ctx, replaced_tokens)
	return destroyed

func _init_token_base_value(tok, min_value: int = 1) -> void:
	if tok == null:
		return
	if not (tok as Object).has_method("get"):
		return
	_ensure_token_uid(tok)
	var base: int = min_value
	var has_meta_flag: bool = false
	if (tok as Object).has_method("has_meta"):
		has_meta_flag = tok.has_meta("base_value")
	if has_meta_flag:
		var bv = tok.get_meta("base_value")
		if bv != null:
			base = int(bv)
	else:
		var vv = tok.get("value")
		if vv == null:
			return
		base = int(vv)
	# Enforce base permanent value cannot go below 1
	if base < min_value:
		base = min_value
	if (tok as Object).has_method("set_meta"):
		tok.set_meta("base_value", base)
	# Apply per-run offset for this token type
	var total_off := _compute_permanent_offset(tok)
	var final_val := base + total_off
	if final_val < min_value:
		final_val = min_value
	if (tok as Object).has_method("set"):
		tok.set("value", final_val)

func _collect_on_removed_commands(ctx: Dictionary, removed_token) -> Array:
	var out: Array = []
	if removed_token == null:
		return out
	# Collect ON_REMOVED ability commands if authored
	var abilities = _get_abilities(removed_token)
	for ab in abilities:
		if ab == null:
			continue
		# trigger check: allow explicit ON_REMOVED or the presence of the builder method
		var trig = ab.get("trigger")
		var ok_trig := false
		if typeof(trig) == TYPE_INT:
			ok_trig = int(trig) == 2 # TokenAbility.Trigger.ON_REMOVED
		elif typeof(trig) == TYPE_STRING:
			ok_trig = String(trig).to_lower().findn("removed") != -1
		if (ab as Object).has_method("build_on_removed_commands"):
			if not ok_trig and debug_spin:
				pass
			var arr = ab.call("build_on_removed_commands", ctx, removed_token, removed_token)
			if arr is Array:
				for cmd in arr:
					if typeof(cmd) == TYPE_DICTIONARY:
						out.append(cmd)

	# Fallback for Executive if no ability authored
	var name_l := _token_name(removed_token).to_lower()
	if name_l == "executive" or _token_has_tag(removed_token, "executive"):
		var destroyed := _destroy_inventory_coins(2, ctx)
		if debug_spin and destroyed > 0:
			print("[Executive] Destroyed %d coin(s) on removal" % destroyed)

	return out

func _register_ward_offset(ctx: Dictionary, off: int) -> void:
	if ctx == null: return
	var arr: Array = ctx.get("ward_offsets", [])
	if not (arr is Array): arr = []
	(arr as Array).append(off)
	ctx["ward_offsets"] = arr

func _resolve_ward_redirect(ctx: Dictionary, contribs: Array, target_off: int) -> int:
	if ctx == null: return target_off
	var wards = ctx.get("ward_offsets", [])
	if not (wards is Array):
		return target_off
	# If any ward is adjacent to the target offset, redirect to that ward (prefer left, then right)
	var left := target_off - 1
	var right := target_off + 1
	if (wards as Array).has(left):
		return left
	if (wards as Array).has(right):
		return right
	return target_off
