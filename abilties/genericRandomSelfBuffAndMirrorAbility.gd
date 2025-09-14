# GenericRandomSelfBuffAndMirrorAbility
# Effect:
# - Self phase (Active During Spin): rolls a random add between [min_add, max_add] for the source token,
#   applies it immediately to self, and stores the roll in `store_key` on the token.
# - Final phase (broadcast): reads the stored roll and “mirrors” that exact amount to adjacent neighbors
#   whose tokens have `mirror_tag` (left/right only), emitting targeted add steps by offset.
#
# Usage:
# - Attach to a token and set Trigger = ACTIVE_DURING_SPIN.
# - Configure:
#   - min_add / max_add: inclusive random range (max_add is clamped to be at least min_add).
#   - mirror_tag: neighbors must have this tag to receive the mirrored add.
#   - store_key: token property used to persist the roll across phases.
# - RNG: prefers ctx.rng when provided; otherwise creates and randomizes a local RNG.
#
# Notes:
# - If no roll occurred (amt == 0) or no matching neighbors, final-phase emits no steps.
# - Mirroring targets immediate neighbors from contribs; to mirror to all tagged tokens on the board,
#   change the targeting to use target_kind = "tag" instead of per-offset neighbors.
# - Consider clearing or decaying `store_key` after use if reuse across spins isn’t desired.

extends TokenAbility
class_name GenericRandomSelfBuffAndMirrorAbility

@export var min_add: int = 1
@export var max_add: int = 10
@export var mirror_tag: String = "coin"
@export var store_key: String = "last_roll"

func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN or contrib.get("token") != source_token: return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"): rng.randomize()
	var amt := rng.randi_range(min_add, max(max_add, min_add))
	source_token.set(store_key, amt)
	return [_mk_add(amt, "Random buff +%d" % amt, "ability:%s"%id)]

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var out: Array = []
	var amt_v = source_token.get(store_key)
	var amt: int = int(amt_v) if amt_v != null else 0
	if amt == 0: return out
	var self_c := _find_self_contrib(contribs, source_token)
	for nc in _adjacent_contribs(contribs, self_c):
		if _token_has_tag(nc.get("token"), mirror_tag):
			out.append({"kind":"add","amount":amt,"factor":1.0,"desc":"Mirror +%d"%amt,"source":"ability:%s"%id,"target_kind":"offset","target_offset":int(nc.get("offset",0))})
	return out
