# GenericPreventDecreasesFilterAbility
# Effect:
# - Filters incoming steps on the source token and cancels decreases based on toggles:
#   - block_negative_add: cancels "add" steps with amount < 0.
#   - block_mult_below_one: cancels "mult" steps with factor < 1.0.
# - Applies only to self (the step’s target_token must equal source_token).
#
# Usage:
# - Attach to a token and set the toggles you want to enforce.
# - Works for both per-token steps and winner broadcast steps, since the executor calls filter_step per target.
#
# Notes:
# - Returning null cancels a step; returning the original (or mutated) Dictionary keeps it.
# - To protect allies too, relax or remove the self-check (target_token != source_token).
# - You can clamp instead of cancel by mutating the step (e.g., set factor = 1.0) and returning it.

extends TokenAbility
class_name GenericPreventDecreasesFilterAbility

@export var block_negative_add: bool = true
@export var block_mult_below_one: bool = true

func filter_step(ctx: Dictionary, step: Dictionary, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}) -> Variant:
	# Only enforce for self (target token is the same as the source token)
	if target_token != source_token:
		return step  # keep unchanged

	var kind := String(step.get("kind", ""))
	if block_negative_add and kind == "add" and int(step.get("amount", 0)) < 0:
		return null  # cancel the step
	if block_mult_below_one and kind == "mult" and float(step.get("factor", 1.0)) < 1.0:
		return null  # cancel the step

	return step
