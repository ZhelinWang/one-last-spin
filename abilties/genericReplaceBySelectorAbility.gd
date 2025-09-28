# GenericReplaceBySelectorAbility
# Effect:
# - During Active During Spin, inspects the current contribs (winner + neighbors) and selects the token with the
#   LOWEST or HIGHEST computed value (base + delta) * mult at this moment.
# - On ties, picks using `tie_break`: "leftmost", "rightmost", or "random" (uses ctx.rng if provided).
# - Emits a command to replace the selected slot with `replace_with_path`.
#   - If preserve_value_from_selected = true, passes the selected value via set_value so the replacement starts with it.
#   - Otherwise sends set_value = -1, signaling the executor to use the replacementÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢s default value.
#   - preserve_tags = true so the executor can carry over tags from the removed token if desired.
#
# Usage:
# - Attach to a token and set Trigger = ACTIVE_DURING_SPIN.
# - Configure:
#   - selector: LOWEST or HIGHEST.
#   - replace_with_path: resource path of the replacement token.
#   - preserve_value_from_selected: whether to seed the new tokenÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢s value with the selected contribÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢s value.
#   - tie_break: how to resolve ties ("leftmost" | "rightmost" | "random").
# - RNG: If ctx.rng isnÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢t present, the script creates and randomizes a local RNG.
#
# Executor requirements:
# - Support command:
#   { op: "replace_at_offset", offset:int, token_path:String, set_value:int, preserve_tags:bool }
#   - set_value = -1 means ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“use replacementÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢s default valueÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â.
#   - If preserve_tags is true, consider merging or copying tags from the removed token to the new one.
#
# Notes:
# - Selection uses current contrib values at the time of execution (after preceding steps).
# - Works on the visible five-slot contrib set; adapt if you need board-wide selection.

extends TokenAbility
class_name GenericReplaceBySelectorAbility

enum Selector { LOWEST, HIGHEST, RANDOM_NEIGHBOR }
## How the target is chosen:
## - LOWEST/HIGHEST: pick the lowest/highest current value among visible slots (excluding self for add op)
## - RANDOM_NEIGHBOR: pick a random adjacent slot
@export var selector: Selector = Selector.LOWEST

## Replacement token resource path (used when op == "replace").
@export var replace_with_path: String = "res://tokens/Hoarder/coin.tres"

## If true, seed the new token's value with the selected token's current value; otherwise use replacement default.
@export var preserve_value_from_selected: bool = true

## When multiple candidates tie, pick using: "leftmost" | "rightmost" | "random".
@export var tie_break: String = "leftmost"  # "leftmost" | "rightmost" | "random"

## If true, copy tags from the removed token to the replacement.
@export var preserve_tags: bool = false      # if true, carry over tags from removed token

# Extended operation modes beyond replacement
## Operation mode:
## - "replace": replace the selected token
## - "add": add amount to the selected target (and optionally scale self after)
@export var op: String = "replace"

## How the add amount is computed when op == "add":
## - "fixed": use `amount` as-is
## - "self_value": use self's current computed value
@export var amount_mode: String = "fixed"

## Amount to use when amount_mode == "fixed".
@export var amount: int = 0

## When op == "add": if true, multiply self by `self_factor` after adding to target.
@export var apply_self_mult_after: bool = false

## Self multiplier factor (e.g., 0.5 halves self).
@export var self_factor: float = 1.0

## When amount_mode == "self_value" and apply_self_mult_after == true:
## use the amount of value self loses from the multiplication as the add amount to target.
@export var use_self_loss_for_amount: bool = false

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
		var self_val := _contrib_value(self_c)
		amt_to_add = self_val
		if use_self_loss_for_amount and apply_self_mult_after:
			var loss := _compute_self_loss(self_c, self_factor)
			if loss > 0:
				amt_to_add = loss
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

func _compute_self_loss(contrib: Dictionary, factor: float) -> int:
	if contrib.is_empty():
		return 0
	var sum: int = int(contrib.get("base", 0)) + int(contrib.get("delta", 0))
	if sum < 0:
		sum = 0
	var mult_before: float = float(max(float(contrib.get("mult", 1.0)), 0.0))
	var pre_val: int = int(floor(float(sum) * mult_before))
	var mult_after: float = mult_before * float(max(factor, 0.0))
	var post_val: int = int(floor(float(sum) * mult_after))
	return max(pre_val - post_val, 0)
