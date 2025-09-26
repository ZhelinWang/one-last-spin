# GenericSetFromContextAbility
# Effect:
# - During Active During Spin, sets the winner/self’s contribution toward a target derived from run context,
#   by emitting an “add” step equal to (target - current_value).
# - Current_value is the contrib’s (base + delta) * mult at the time this runs.
# - With compute = PERCENT_OF_BANK, target = floor(run_total * percent), using ctx.run_total.
#
# Usage:
# - Attach to a token and set Trigger = ACTIVE_DURING_SPIN.
# - Configure:
#   - compute: PERCENT_OF_BANK (more modes can be added later).
#   - percent: fraction of bank/run_total to target (e.g., 0.10 → 10%).
# - Keep target_kind = SELF if you intend to set the winner’s own value; changing target_kind will direct the add elsewhere
#   since mk_global_step uses the ability’s target fields for routing.
#
# Notes:
# - If target equals the current contrib value, no step is emitted.
# - run_total is read from ctx; ensure your CoinManager passes it (this script falls back to 0 when missing).
# - Negative or NaN scenarios are clamped away: bank and percent are treated as >= 0 before computing target.

extends TokenAbility
class_name GenericTransferAndSelfScaleAbility

## For adjacency checks: if true, pass when at least one neighbor matches; otherwise require all neighbors to match.
@export var require_any: bool = true

## Amount to add to self when the condition passes.
@export var amount: int = 1

## Match by tag on neighbors, e.g., "coin", "worker" (case-insensitive).
@export var match_tag: String = ""

## Alternative to tag: match by exact token name on neighbors.
@export var match_name: String = ""

func _match_token(tok) -> bool:
	if match_tag.strip_edges() != "": return _token_has_tag(tok, match_tag)
	if match_name.strip_edges() != "": return _token_name(tok).to_lower() == match_name.to_lower()
	return false

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var out: Array = []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty(): return out
	var hits: int = 0
	for nc in _adjacent_contribs(contribs, self_c):
		if _match_token(nc.get("token")):
			hits += 1
	if (require_any and hits > 0) or (not require_any and hits == _adjacent_contribs(contribs, self_c).size()):
		var merged = _mk_add(amount, "Adjacency buff", "ability:%s" % id).duplicate()
		merged.merge({"target_kind": "self"}, true)
		out.append(merged)
	return out
