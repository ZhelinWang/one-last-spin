# GenericInventoryReplaceAndAdjustAbility
# Effect:
# - During the winner’s final phase, checks how many tokens on the board have `tag`.
# - If that count is below `threshold`, applies a multiplier to SELF:
#   - factor = `count` when `factor_equals_count` is true (e.g., 0→x0, 1→x1, 2→x2, …),
#   - otherwise factor = 2.0 (static fallback).
# - Emits a single “mult” step targeting self (not a broadcast).
#
# Usage:
# - Attach to a token and set Trigger = ACTIVE_DURING_SPIN.
# - Configure:
#   - tag: which tag to count on the board (ctx.board_tokens must be provided).
#   - threshold: only buff when count < threshold.
#   - factor_equals_count: dynamic scaling vs fixed x2.0.
#
# Notes:
# - Counting is done via ctx.board_tokens; if the source token has the tag, it’s included in the count.
# - A count of 0 with factor_equals_count = true yields x0 (zeroes output). If that’s not desired,
#   clamp the factor to a minimum (e.g., max(count, 1)) before emitting.
# - To affect others instead of self, change the emitted step’s target_kind accordingly (e.g., "neighbors" or "tag").

extends TokenAbility
class_name GenericInventoryReplaceAndAdjustAbility

@export var tag: String = "coin"
@export var threshold: int = 5
@export var factor_equals_count: bool = true

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var out: Array = []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty(): return out
	var count := _count_in_inventory(ctx, tag)
	if count < threshold:
		var factor: float = float(count) if factor_equals_count else 2.0
		out.append({"kind":"mult","amount":0,"factor":factor,"desc":"Conditional mult","source":"ability:%s"%id,"target_kind":"self"})
	return out
