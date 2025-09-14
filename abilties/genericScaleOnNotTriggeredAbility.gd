# GenericScaleOnNotTriggeredAbility
# Effect:
# - Tracks a per-token “scale” stored in `meta_key` and increases it every spin where the token does NOT trigger.
# - New value each miss: scale = scale * max(1.0, factor); initial value is `base_value` when unset.
# - Provides `reset_scale()` so a companion ability (or executor) can reset the scale after a successful trigger.
#
# Usage:
# - Attach to a token and ensure your executor calls `on_not_triggered(ctx, source_token)` for tokens that didn’t fire
#   (e.g., non-winner or condition failed).
# - Other abilities can read `source_token.get(meta_key)` to multiply or add by the current scale when they do trigger.
# - Call `reset_scale(source_token)` after applying the scaled effect if `reset_on_trigger` is true.
#
# Config:
# - meta_key: property name used to store the scale (float recommended).
# - factor: growth multiplier per miss (clamped to >= 1.0).
# - base_value: starting scale when no value is set.
# - reset_on_trigger: whether `reset_scale` sets the stored value back to `base_value`.
#
# Notes:
# - This ability doesn’t emit steps/commands; it only updates the token’s stored property.
# - Consider clamping or capping scale elsewhere to prevent runaway growth.
# - If you use the scale for integer effects, round as needed when consuming it.

extends TokenAbility
class_name GenericScaleOnNotTriggeredAbility

@export var meta_key: String = "scale"
@export var factor: float = 1.5
@export var reset_on_trigger: bool = true
@export var base_value: int = 1

func on_not_triggered(ctx: Dictionary, source_token: Resource) -> void:
	var cur = source_token.get(meta_key)
	var v: float = float(cur) if cur != null else float(base_value)
	source_token.set(meta_key, v * max(1.0, factor))

# Call this from a companion ability (e.g., your permanent adjust) after success:
func reset_scale(source_token: Resource) -> void:
	if reset_on_trigger:
		source_token.set(meta_key, base_value)
