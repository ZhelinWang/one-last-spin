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

enum Selector { LOWEST, HIGHEST }
@export var selector: Selector = Selector.LOWEST
@export var replace_with_path: String = "res://tokens/coin.tres"
@export var preserve_value_from_selected: bool = true
@export var tie_break: String = "leftmost"  # "leftmost" | "rightmost" | "random"
@export var preserve_tags: bool = false      # if true, carry over tags from removed token

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN or contribs.is_empty(): return []
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
