# GenericDoubleChangeReactiveAbility
# Effect:
# - Reacts after any value change on the source token during a spin and adds an extra change equal to:
#   extra = (multiplier - 1) * delta, where delta = new_val - prev_val.
# - With multiplier = 2.0 (default), all increases/decreases are doubled; e.g., +5 becomes +10, -3 becomes -6.
# - Applies only to self (the changed token must be the source); remove the equality check to affect others.
#
# Usage:
# - Attach to a token and set `multiplier` (>= 0). Values > 1 amplify changes; values between 0 and 1 dampen them.
# - Requires CoinManager to invoke ability `on_value_changed` after each applied step (already supported in your manager).
# - This mutates the contrib’s delta directly; it doesn’t emit a separate step, so there’s no extra popup by default.
#   If you want visible feedback, adapt your executor to enqueue a real “add” step for `extra`.
#
# Notes:
# - No effect when delta == 0.
# - Negative deltas remain negative; the ability will amplify/dampen decreases the same as increases.
# - Multiplier is clamped at 0 for safety.

extends TokenAbility
class_name GenericDoubleChangeReactiveAbility

@export var multiplier: float = 2.0

func on_value_changed(ctx: Dictionary, prev_val: int, new_val: int, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}, step: Dictionary = {}) -> void:
	# Only react for self (the changed token is the source)
	if target_token != source_token:
		return

	var delta := new_val - prev_val
	if delta == 0:
		return

	var extra := int(round(float(delta) * (max(multiplier, 0.0) - 1.0)))
	if extra == 0:
		return

	# Apply the extra change directly to the contrib
	var d := int(target_contrib.get("delta", 0))
	target_contrib["delta"] = d + extra
