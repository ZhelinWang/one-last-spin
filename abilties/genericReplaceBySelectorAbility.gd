# GenericReplaceBySelectorAbility
# Effect:
# - During Active During Spin, inspects the current contribs (winner + neighbors) and selects the token with the
#   LOWEST or HIGHEST computed value (base + delta) * mult at this moment.
# - On ties, picks using `tie_break`: "leftmost", "rightmost", or "random" (uses ctx.rng if provided).
# - Emits a command to replace the selected slot with `replace_with_path`.
#   - If preserve_value_from_selected = true, passes the selected value via set_value so the replacement starts with it.
#   - Otherwise sends set_value = -1, signaling the executor to use the replacement’s default value.
#   - preserve_tags = true so the executor can carry over tags from the removed token if desired.
#
# Usage:
# - Attach to a token and set Trigger = ACTIVE_DURING_SPIN.
# - Configure:
#   - selector: LOWEST or HIGHEST.
#   - replace_with_path: resource path of the replacement token.
#   - preserve_value_from_selected: whether to seed the new token’s value with the selected contrib’s value.
#   - tie_break: how to resolve ties ("leftmost" | "rightmost" | "random").
# - RNG: If ctx.rng isn’t present, the script creates and randomizes a local RNG.
#
# Executor requirements:
# - Support command:
#   { op: "replace_at_offset", offset:int, token_path:String, set_value:int, preserve_tags:bool }
#   - set_value = -1 means “use replacement’s default value”.
#   - If preserve_tags is true, consider merging or copying tags from the removed token to the new one.
#
# Notes:
# - Selection uses current contrib values at the time of execution (after preceding steps).
# - Works on the visible five-slot contrib set; adapt if you need board-wide selection.

extends TokenAbility
class_name GenericReplaceBySelectorAbility

enum Selector { LOWEST, HIGHEST, RANDOM_NEIGHBOR }
@export var selector: Selector = Selector.LOWEST
@export var replace_with_path: String = "res://tokens/coin.tres"
@export var preserve_value_from_selected: bool = true
@export var tie_break: String = "leftmost"  # "leftmost" | "rightmost" | "random"
@export var preserve_tags: bool = false      # if true, carry over tags from removed token

# Extended operation modes beyond replacement
@export var op: String = "replace"          # "replace" | "add"
@export var amount_mode: String = "fixed"    # "fixed" | "self_value"
@export var amount: int = 0                  # used when amount_mode == "fixed"
@export var apply_self_mult_after: bool = false
@export var self_factor: float = 1.0         # e.g., 0.5 to halve self

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN or contribs.is_empty(): return []
	if op != "replace":
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"): rng.randomize()

	var chosen: Dictionary = {}
	var best_val: int = 999999 if selector == Selector.LOWEST else -999999
	var cands: Array = []
	for c in contribs:
		var v := _contrib_value(c)
		if (selector == Selector.LOWEST and v < best_val) or (selector == Selector.HIGHEST and v > best_val):
			best_val = v
			cands = [c]
		elif v == best_val:
			cands.append(c)
	if cands.is_empty(): return []
	match tie_break:
		"rightmost": chosen = cands.back()
		"random": chosen = cands[rng.randi_range(0, cands.size()-1)]
		_: chosen = cands[0]
	return [{
		"op":"replace_at_offset",
		"offset": int(chosen.get("offset",0)),
		"token_path": replace_with_path,
		"set_value": (best_val if preserve_value_from_selected else -1),
		"preserve_tags": preserve_tags
	}]

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN or op != "add":
		return []
	var out: Array = []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return out

	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"): rng.randomize()

	var target_off := 0
	if selector == Selector.RANDOM_NEIGHBOR:
		var offs: Array = []
		for nc in _adjacent_contribs(contribs, self_c):
			offs.append(int(nc.get("offset", 0)))
		if offs.is_empty():
			# still allow self mult after, if requested
			if apply_self_mult_after and self_factor != 1.0:
				out.append({"kind":"mult","amount":0,"factor":self_factor,"desc":"Self mult","source":"ability:%s"%id,"target_kind":"self"})
			return out
		target_off = offs[rng.randi_range(0, offs.size()-1)]
	else:
		# fallback: select LOWEST/HIGHEST among the five (excluding self if desired)
		var chosen: Dictionary = {}
		var best_val: int = 999999 if selector == Selector.LOWEST else -999999
		var cands: Array = []
		for c in contribs:
			if c.get("token") == source_token:
				continue
			var v := _contrib_value(c)
			if (selector == Selector.LOWEST and v < best_val) or (selector == Selector.HIGHEST and v > best_val):
				best_val = v
				cands = [c]
			elif v == best_val:
				cands.append(c)
		if cands.is_empty():
			return out
		var chosen_c = cands[0]
		target_off = int(chosen_c.get("offset", 0))

	# Amount to add
	var amt_to_add: int = amount
	if amount_mode == "self_value":
		amt_to_add = _contrib_value(self_c)
	if amt_to_add != 0:
		out.append({
			"kind": "add",
			"amount": amt_to_add,
			"factor": 1.0,
			"desc": "+%d via selector" % amt_to_add,
			"source": "ability:%s" % id,
			"target_kind": "offset",
			"target_offset": target_off
		})

	if apply_self_mult_after and self_factor != 1.0:
		out.append({
			"kind": "mult",
			"amount": 0,
			"factor": max(self_factor, 0.0),
			"desc": "Self mult",
			"source": "ability:%s" % id,
			"target_kind": "self"
		})

	return out
