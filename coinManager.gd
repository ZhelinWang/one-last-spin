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

# rarity tokens
@export var empty_non_common_bonus_per: float = 0.03  # 3% per Empty

# Loot signals
signal loot_choice_needed(round_number: int)
signal loot_choice_selected(round_number: int, token)
signal loot_choice_replaced(round_number: int, token, index: int) # replaces first/last/random empty in inventory

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
@export var ante_schedule: PackedInt32Array = [25, 45, 65, 95, 125, 170, 220, 300, 390, 500, 620, 777, 950, 1100, 1300, 1500, 1700, 1900, 2200, 2500]
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
@export var loot_title: String = "ROUND COMPLETE\n\nCHOOSE A TOKEN TO REPLACE AN EMPTY TOKEN"
@export var skip_button_text: String = "SKIP AND ADD AN EMPTY TOKEN"
# Assign your slotItem scene here (extends Button, property `data: TokenLootData`)
@export var token_icon_scene: PackedScene
# Scale factor for tiles/icons (3x requested)
@export var loot_tile_scale: float = 3.0

# Inventory wiring for replacement
@export var inventory_owner_path: NodePath
@export var inventory_property: String = "items"
@export_enum("first", "last", "random") var empty_replace_strategy: String = "first"

# Debugging
@export var debug_spin: bool = true

var total_active: int = 0
var total_passive: int = 0
var total_coins: int = 0
var spin_index: int = 0

var _artifacts: Array[ArtifactData] = []
var _totals_owner: Node = null # %valueLabel, %roundLabel, %deadlineLabel

# Game Over overlay
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
const META_ZERO_REPLACED := "__zero_replaced"
const META_ZERO_REASON := "__zero_reason"
const ZERO_REPLACEMENT_VALUE := 1


func _ready() -> void:
	_loot_rng.randomize()
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
func set_artifacts_order(effects: Array) -> void:
	_artifacts = []
	for e in effects:
		if e is ArtifactData:
			_artifacts.append(e)

func register_artifact(effect: ArtifactData) -> void:
	if effect and not _artifacts.has(effect):
		_artifacts.append(effect)

func unregister_artifact(effect: ArtifactData) -> void:
	if effect:
		_artifacts.erase(effect)

func clear_artifacts() -> void:
	_artifacts.clear()

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
	if is_instance_valid(_bank_tween):
		_bank_tween.kill()
	_bank_tween = null
	_update_totals_label(total_coins)
	_update_round_and_deadline_labels()
	_update_spin_counters(true)
	_hide_game_over()
	_hide_loot_overlay()
	emit_signal("game_reset")

# ---------- Spin sequence ----------
func begin_spin() -> void:
	# Increment the run spin index and refresh UI immediately on button press
	spin_index += 1
	_update_spin_counters(false)

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

	# winner active steps (self) deferred here; winner global active (affect others) collected later
	var deferred_winner_self_steps: Array = []

	# Per-token sequence in strict order:
	# 1) base popup; 2) token passive; 3) artifacts; (winner active deferred)
	for i in range(contribs.size()):
		var c: Dictionary = contribs[i]
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

		# Do not scale self-target permanent_add here; visuals will display per-matching token separately
		# Stash board visual commands in ctx for the broadcast phase to run right after the active label shake
		var need_board_phase := not board_visual_cmds.is_empty() or not post_shake_cmds.is_empty()
		if not board_visual_cmds.is_empty():
			ctx["__board_visual_cmds"] = board_visual_cmds
			ctx["__ran_replace_board_tag"] = true
		if not post_shake_cmds.is_empty():
			ctx["__post_shake_cmds"] = post_shake_cmds
			ctx["__ran_permanent_add"] = true
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

	# Re-finalize after global active so totals include all effects
	for k in range(contribs.size()):
		var ck: Dictionary = contribs[k]
		ck.meta["final"] = _finalize_contrib(ck)
		if debug_spin:
			print("[Spin] Final offset=", ck.offset, " => ", ck.meta["final"])

	# Compute totals ONCE per spin
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

	# Reverted: directly update totals without extra overlay animations
	_update_totals_label(total_coins)
	_update_spin_counters(false)

	# Build result dictionary without multi-line literal
	result = {}
	result["active_total"] = active_total
	result["passive_total"] = passive_total
	result["spin_total"] = spin_total
	result["run_total"] = total_coins
	result["contributions"] = contribs
	result["context"] = ctx
	if debug_spin:
		print("[Totals] active=", active_total, " passive=", passive_total, " spin_total=", result["spin_total"], " run_total=", total_coins)
	emit_signal("spin_totals_ready", result)

	# After computing totals, execute any winner ability commands
	# These mutate inventory for future spins (e.g., replace lowest with Coin)
	var _cmds := _collect_winner_ability_commands(ctx, contribs, winner)
	if _cmds is Array and not _cmds.is_empty():
		# Filter out early-run inventory ops
		var skip_empties := bool(ctx.get("__ran_replace_all_empties", false))
		var skip_perm := bool(ctx.get("__ran_permanent_add", false))
		var skip_board := bool(ctx.get("__ran_replace_board_tag", false))
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
			late.append(cmd)
		if not late.is_empty():
			if debug_spin:
				print("[Commands] Found ", late.size(), " command(s). Executing...")
			_execute_ability_commands(late, ctx, contribs)

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

		var prev_val: int = _compute_value(c)
		if debug_spin:
			print("	[Apply] offset=", c.offset, " kind=", stepn.get("kind"), " +", stepn.get("amount", 0), " x", stepn.get("factor", 1.0), " src=", stepn.get("source", "unknown"))
		if not _is_contrib_zero_replaced(c):
			_shake_slot_for_contrib(ctx, c)
		_apply_step(c, stepn)
		var new_val: int = _compute_value(c)

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
		_play_counting_popup(ctx, c, prev_val, new_val, false)

		# Ability on_value_changed hooks (target + source)
		_invoke_on_value_changed(ctx, source_token, c, prev_val, new_val, stepn)

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

func _shake_slot_for_contrib(ctx: Dictionary, contrib: Dictionary) -> void:
	if ctx == null or contrib == null:
		return
	var off := int(contrib.get("offset", 0))
	var slot := _slot_from_ctx(ctx, off)
	if slot != null:
		_shake_slot(slot)

# NEW: Apply one global step across multiple tokens simultaneously
func _apply_global_step_parallel(step: Dictionary, contribs: Array, indices: Array, ctx: Dictionary) -> void:
	# Snapshot previous values
	var prev_vals: Array[int] = []
	prev_vals.resize(indices.size())
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
		_shake_slot_for_contrib(ctx, c)
		_apply_step(c, step)

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
		_play_counting_popup(ctx, c, prev_vals[k], _compute_value(c), false)

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
func _play_counting_popup(ctx: Dictionary, contrib: Dictionary, from_val: int, to_val: int, is_base: bool) -> void:
	var env := _ensure_popup(ctx, contrib)
	if env.is_empty():
		return
	var popup := env["popup"] as Control
	var slot := env["slot"] as Control

	var delta: int = int(abs(to_val - from_val))
	var count_dur: float = clamp(0.06 + float(delta) * 0.015, 0.12, 0.30)

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

	var ct := get_tree().create_tween()
	popup.set_meta("count_tween", ct)
	var call := Callable(self, "_set_counting_text").bind(env["label"])
	ct.tween_method(call, float(from_val), float(to_val), count_dur).set_trans(Tween.TRANS_LINEAR)

func _set_counting_text(v: float, target: Node) -> void:
	if target == null:
		return
	var t := "+%d%s" % [int(round(v)), _gold_bbcode()]
	if target is Label:
		(target as Label).text = t
	elif target is RichTextLabel:
		var rtl := target as RichTextLabel
		if rtl.bbcode_enabled:
			rtl.bbcode_text = t
		else:
			rtl.text = t

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
			var lbl := Label.new()
			lbl.name = "valueLabel"
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
	var requirement: int = _get_requirement_for_round(round_num)
	var paid: bool = false
	if total_coins >= requirement:
		paid = true
		if deduct_on_pay:
			total_coins -= requirement
			_update_totals_label(total_coins)
			emit_signal("round_ended", round_num, requirement, true)
			_update_spin_counters()
		_trigger_loot_choice(round_num)
	else:
		emit_signal("round_ended", round_num, requirement, false)
		_trigger_game_over(round_num, requirement)
		_update_spin_counters()

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

func _set_value_label_gold(total: int) -> void:
	var lbl := _resolve_value_label()
	if lbl == null:
		return
	var s := "%d%s" % [total, _gold_bbcode()]
	if lbl is RichTextLabel:
		(lbl as RichTextLabel).set_deferred("bbcode_text", s)
	else:
		_set_node_text(lbl, s)

func _update_totals_label(total: int) -> void:
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

func _apply_step(c: Dictionary, step: Dictionary) -> void:
	var before: Dictionary = {
		"base": int(c.base),
		"delta": int(c.delta),
		"mult": float(c.mult),
		"val": _compute_value(c)
	}
	if step.get("kind", "") == "add":
		c.delta = int(c.delta) + int(step.get("amount", 0))
	elif step.get("kind", "") == "mult":
		var f: float = float(step.get("factor", 1.0))
		if f < 0.0:
			f = 0.0
		c.mult = float(c.mult) * f
	if int(c.base) + int(c.delta) < 0:
		c.delta = -int(c.base)
	if float(c.mult) < 0.0:
		c.mult = 0.0
	var after: Dictionary = {
		"base": int(c.base),
		"delta": int(c.delta),
		"mult": float(c.mult),
		"val": _compute_value(c)
	}
	var mult_applied: float = 0.0
	if float(before.mult) != 0.0:
		mult_applied = float(after.mult) / float(before.mult)
	else:
		mult_applied = float(after.mult)

	var logged: Dictionary = {
		"source": step.get("source", "unknown"),
		"kind": step.get("kind", ""),
		"desc": step.get("desc", ""),
		"before": before,
		"after": after,
		"add_applied": int(after.delta) - int(before.delta),
		"mult_applied": mult_applied
	}
	(c.steps as Array).append(logged)

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
						(parts["deferred"] as Array).append(_normalize_step(s))
					if debug_spin: print("  [Ability] +steps (deferred winner_only): ", arr.size())
				else:
					for s in arr:
						(parts["immediate"] as Array).append(_normalize_step(s))
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
		if is_winner_only and is_winner_slot:
			(parts["deferred"] as Array).append(step)
			if debug_spin: print("  [Ability] +autostep (deferred winner_only): ", step)
		else:
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

	var desc := ""
	if winner != null and winner.has_method("get"):
		var ad = winner.get("activeDescription")
		if typeof(ad) == TYPE_STRING:
			desc = String(ad).strip_edges()
	if desc == "":
		desc = "No active effect."

	var title_hex := "#f62c25"
	if lbl is RichTextLabel:
		var rtl := lbl as RichTextLabel
		rtl.bbcode_enabled = true
		rtl.bbcode_text = "[color=%s]%s:[/color] %s" % [title_hex, title.to_upper(), desc.to_upper()]
	else:
		_set_node_text(lbl, "%s\n%s" % [title.to_upper(), desc.to_upper()])

func _resolve_active_effect_label() -> Node:
	if _active_effect_label != null and is_instance_valid(_active_effect_label):
		return _active_effect_label
	_active_effect_label = _resolve_ui_node(_owner_node(), "%activeEffect", "activeEffect")
	return _active_effect_label

# ---------- Loot overlay + picking ----------
func _trigger_loot_choice(round_num: int) -> void:
	# Do not offer loot if a Game Over is active
	if _game_over_active:
		return
	var options: Array = _get_loot_options(max(1, loot_options_count), round_num)
	if options.is_empty():
		_on_loot_skip_pressed(round_num)
		return
	_build_loot_overlay_if_needed()
	var gen := _loot_gen
	_show_loot_overlay(round_num, options, gen)
	emit_signal("loot_choice_needed", round_num)

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

	_loot_last_round = round_num

	print("[Loot] Offered options for round ", round_num, ":")
	for i in range(options.size()):
		var t = options[i]
		if t != null and t.has_method("get"):
			print("  - ", String(t.get("name")), " | rarity=", t.get("rarity"), " | value=", t.get("value"), " | weight=", t.get("weight"))

	_clear_children(_loot_options_hbox)

	var SLOT_BASE := 96
	var TILE_BASE := 96
	var ICON_BASE := 64
	var slot_px := int(round(SLOT_BASE * loot_tile_scale))
	var tile_px := int(round(TILE_BASE * loot_tile_scale))
	var icon_px := int(round(ICON_BASE * loot_tile_scale))

	for token in options:
		# Ensure loot shows the current per-run adjusted value
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

		if token_icon_scene != null:
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

func _on_loot_pressed_node(node: Button) -> void:
	var token: Resource = node.get_meta("token_data") as Resource
	_emit_loot_selected(_loot_last_round, token)

func _on_loot_skip_pressed(round_num: int) -> void:
	var token: Resource = _load_empty_token()
	_emit_loot_selected(round_num, token)

func _emit_loot_selected(round_num: int, token: Resource) -> void:
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
	if sched == null:
	# No schedule: legacy fallback (global weighting, not rarity-aware)
		return _pick_weighted_unique(pool, count, _loot_rng)

	# Base schedule → apply runtime rarity modifiers (e.g., Empties, artifacts via manager) → pick
	var base_weights: Dictionary = sched.get_rarity_weights(round_num)
	var adjusted: Dictionary = _apply_rarity_modifiers(base_weights, round_num, _loot_rng)

	return _pick_with_rarity_schedule(pool, count, _loot_rng, round_num, sched, adjusted)
	
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
		return int(rng.randi_range(0, indices.size() - 1))
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

func _token_key(t) -> String:
	if t is Resource and (t as Resource).resource_path != "":
		return String((t as Resource).resource_path)
	var nm := _token_name(t).strip_edges().to_lower()
	if nm != "":
		return nm
	return str(t)

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
	await _pause(active_desc_pause_sec)

	# After the active effect label shake, run any board-visual commands (e.g., Mint replacing coins on board)
	var __board_cmds = ctx.get("__board_visual_cmds")
	if __board_cmds is Array and not (__board_cmds as Array).is_empty():
		if debug_spin:
			print("[Board-Visual] Executing ", int((__board_cmds as Array).size()), " command(s) after shake")
		_execute_ability_commands(__board_cmds, ctx, contribs)

	# Also run any post-shake inventory commands (e.g., Hustler permanent_add) before totals
	var __post_cmds = ctx.get("__post_shake_cmds")
	if __post_cmds is Array and not (__post_cmds as Array).is_empty():
		if debug_spin:
			print("[Post-Shake] Executing ", int((__post_cmds as Array).size()), " inventory command(s)")
		_execute_ability_commands(__post_cmds, ctx, contribs)

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
				var pv: int = _compute_value(c2)
				var nv: int = pv + self_amt
				_play_counting_popup(ctx, c2, pv, nv, false)
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
		return

	# Snapshot previous values per target
	var prev_vals: Dictionary = {}  # idx -> int
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
			_shake_slot_for_contrib(ctx, c)
			_apply_step(c, stepn)

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
		_play_counting_popup(ctx, c, int(prev_vals[idx]), _compute_value(c), false)

	# Ability on_value_changed once per target for the batch
	for i in targets:
		var idx := int(i)
		var c: Dictionary = contribs[idx]
		if _is_contrib_zero_replaced(c):
			continue
		_invoke_on_value_changed(ctx, winner, c, int(prev_vals[idx]), _compute_value(c), {"kind":"batch","source":"winner_active"})

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

	# Small positional shake if it's a Control
	if ci is Control:
		var ctrl := ci as Control
		var rng := _mk_rng()
		var orig_pos := ctrl.position
		var shake := get_tree().create_tween()
		var shakes := 3
		var strength: float = 8.0
		for i in range(shakes):
			var offv := Vector2(rng.randf_range(-strength, strength), rng.randf_range(-strength, strength))
			shake.tween_property(ctrl, "position", orig_pos + offv, 0.03).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		shake.tween_property(ctrl, "position", orig_pos, 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

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
	return {
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
	if winner == null:
		return out
	if winner.has_method("get"):
		var abilities = winner.get("abilities")
		if abilities is Array:
			for ab in abilities:
				if ab == null:
					continue
				# Only consider Active During Spin and winner_only abilities for commands
				if not _ability_is_active_during_spin(ab):
					continue
				if not _ability_winner_only(ab):
					continue
				if (ab as Object).has_method("build_commands"):
					var arr = ab.build_commands(ctx, contribs, winner)
					if arr is Array:
						for cmd in arr:
							if typeof(cmd) == TYPE_DICTIONARY:
								out.append(cmd)
	return out

func _execute_ability_commands(cmds: Array, ctx: Dictionary, _contribs: Array) -> void:
	for cmd in cmds:
		if typeof(cmd) != TYPE_DICTIONARY:
			continue
		var op := String((cmd as Dictionary).get("op", "")).to_lower()
		match op:
			"replace_at_offset":
				var off := int((cmd as Dictionary).get("offset", 0))
				var token_path := String((cmd as Dictionary).get("token_path", ""))
				var set_value := int((cmd as Dictionary).get("set_value", -1))
				var preserve_tags := bool((cmd as Dictionary).get("preserve_tags", false))
				_replace_token_at_offset(ctx, off, token_path, set_value, preserve_tags)
			"replace_all_empties":
				var token_path2 := String((cmd as Dictionary).get("token_path", ""))
				_replace_all_empties_in_inventory(token_path2)
			"permanent_add":
				var tk := String((cmd as Dictionary).get("target_kind", "any")).to_lower()
				var toff := int((cmd as Dictionary).get("target_offset", 0))
				var ttag := String((cmd as Dictionary).get("target_tag", ""))
				var tname := String((cmd as Dictionary).get("target_name", ""))
				var amt2 := int((cmd as Dictionary).get("amount", 0))
				var diz := bool((cmd as Dictionary).get("destroy_if_zero", false))
				var propagate_same_key := bool((cmd as Dictionary).get("propagate_same_key", false))
				_apply_permanent_add_inventory(tk, toff, ttag, tname, amt2, diz, ctx, propagate_same_key)
			"replace_board_tag":
				var tag := String((cmd as Dictionary).get("target_tag", ""))
				var tpath := String((cmd as Dictionary).get("token_path", ""))
				_replace_board_tag_in_slotmap(ctx, tag, tpath)
			"replace_board_empties":
				var tpath2 := String((cmd as Dictionary).get("token_path", ""))
				_replace_board_empties_in_slotmap(ctx, tpath2)
			"adjust_run_total":
				var amt := int((cmd as Dictionary).get("amount", 0))
				if amt != 0:
					total_coins = max(0, total_coins + amt)
					_update_totals_label(total_coins)
			"destroy":
				var off2 := int((cmd as Dictionary).get("target_offset", (cmd as Dictionary).get("offset", 0)))
				var empty_res := _load_empty_token()
				if empty_res != null and empty_res is Resource:
					_replace_token_at_offset(ctx, off2, (empty_res as Resource).resource_path, -1, false)
			_:
				if debug_spin:
					print("[Commands] Unknown op: ", op)

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

func _replace_token_at_offset(ctx: Dictionary, offset: int, token_path: String, set_value: int, preserve_tags: bool, target_token_override = null) -> Resource:
	if token_path.strip_edges() == "":
		return null
	var slot := _slot_from_ctx(ctx, offset)
	if slot != null:
		_shake_slot(slot)
	var target_token = target_token_override
	if target_token == null and slot != null:
		if slot.has_meta("token_data"):
			target_token = slot.get_meta("token_data")

	# If we have a token to remove, let its abilities react (e.g., on-removed penalties)
	if target_token != null:
		var removed_cmds := _collect_on_removed_commands(ctx, target_token)
		if removed_cmds is Array and not removed_cmds.is_empty():
			_execute_ability_commands(removed_cmds, ctx, [])

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

	var rep := ResourceLoader.load(token_path)
	if rep == null or not (rep is Resource):
		return null
	var inst := (rep as Resource).duplicate(true)
	_init_token_base_value(inst)
	# Optional: set incoming value and preserve tags
	if inst.has_method("set") and set_value >= 0:
		inst.set("value", set_value)
	if preserve_tags:
		var src_tags = null
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

	return inst

func _apply_token_to_slot(slot: Control, token: Resource) -> void:
	if slot == null or token == null:
		return
	# Update meta used everywhere
	slot.set_meta("token_data", token)
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
	var rep := ResourceLoader.load(token_path)
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
			var inst := (rep as Resource).duplicate(true)
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
	var rep := ResourceLoader.load(token_path)
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
			var inst := (rep as Resource).duplicate(true)
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

func _replace_all_empties_in_inventory(token_path: String) -> void:
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
	var rep := ResourceLoader.load(token_path)
	if rep == null or not (rep is Resource):
		return
	var changed := false
	for i in range((arr as Array).size()):
		var it = (arr as Array)[i]
		if _is_empty_token(it):
			var inst := (rep as Resource).duplicate(true)
			_init_token_base_value(inst)
			(arr as Array)[i] = inst
			changed = true
	if changed:
		owner.set(prop, arr)
		if owner.has_method("_update_inventory_strip"):
			owner.call_deferred("_update_inventory_strip")

func _apply_permanent_add_inventory(target_kind: String, target_offset: int, target_tag: String, target_name: String, amount: int, destroy_if_zero: bool, ctx: Dictionary, propagate_same_key: bool = false) -> void:
	var owner := _resolve_inventory_owner_node()
	if owner == null or not owner.has_method("get"):
		return
	var prop := String(inventory_property)
	if prop.strip_edges() == "": prop = "items"
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

	var anchor_token = null
	var anchor_key := ""
	if (target_kind == "self" or target_kind == "offset" or propagate_same_key):
		var anchor_slot := _slot_from_ctx(ctx, target_offset)
		if anchor_slot != null and anchor_slot.has_meta("token_data"):
			anchor_token = anchor_slot.get_meta("token_data")
			anchor_key = _token_key(anchor_token)
	var matches_token = func(tok) -> bool:
		if tok == null:
			return false
		if target_kind == "self" or target_kind == "offset":
			if anchor_token != null:
				return tok == anchor_token
			return false
		var name_ok: bool = true
		var tag_ok: bool = true
		if target_kind == "name" and target_name.strip_edges() != "":
			name_ok = (_token_name(tok) == target_name)
		if target_kind == "tag" and target_tag.strip_edges() != "":
			tag_ok = _token_has_tag(tok, target_tag)
		if target_kind == "any":
			return true
		return name_ok and tag_ok

	# Update per-run offsets for all matched token types
	var affected: Dictionary = {}
	for i in range((arr as Array).size()):
		var tok = (arr as Array)[i]
		var matched: bool = matches_token.call(tok)
		if not matched and propagate_same_key and anchor_key != "":
			matched = (_token_key(tok) == anchor_key)
		if matched:
			var key := _token_key(tok)
			if affected.has(key):
				continue
			var cur := int(_token_value_offsets.get(key, 0))
			_token_value_offsets[key] = cur + amount
			affected[key] = true

	# Apply recalculated value (base + new offset) to all instances of affected types
	var changed := false
	var replaced_tokens: Array = []
	for i in range((arr as Array).size()):
		var tok = (arr as Array)[i]
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
		if curv <= 0:
			var empty_res := _load_empty_token()
			if empty_res is Resource:
				var inst := (empty_res as Resource).duplicate(true)
				_init_token_base_value(inst)
				(arr as Array)[i] = inst
				replaced_tokens.append({"old": orig_token, "new": inst})
				changed = true
				continue
		changed = true

	if changed:
		owner.set(prop, arr)
		if owner.has_method("_update_inventory_strip"):
			owner.call_deferred("_update_inventory_strip")
		if ctx != null and ctx is Dictionary:
			ctx["board_tokens"] = _get_inventory_array()
			if not replaced_tokens.is_empty():
				_update_slot_map_for_replacements(ctx, replaced_tokens)

# Ensure a token tracks its baseline value in metadata so resets can restore it
func _init_token_base_value(tok) -> void:
	if tok == null:
		return
	if not (tok as Object).has_method("get"):
		return
	var base: int = 0
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
		if (tok as Object).has_method("set_meta"):
			tok.set_meta("base_value", base)
	# Apply per-run offset for this token type
	var key := _token_key(tok)
	var off := int(_token_value_offsets.get(key, 0))
	if (tok as Object).has_method("set"):
		tok.set("value", max(0, base + off))

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
		# Lose 5x removed token's value
		var v = 0
		if (removed_token as Object).has_method("get"):
			var vv = removed_token.get("value")
			if vv != null: v = int(vv)
		if v > 0:
			out.append({"op":"adjust_run_total", "amount": -5 * v, "source": "token:Executive", "desc": "Executive removal penalty"})

	return out
