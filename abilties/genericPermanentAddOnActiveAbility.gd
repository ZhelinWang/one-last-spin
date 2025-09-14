# GenericPermanentAddOnActiveAbility
# Effect:
# - During Active During Spin, requests a permanent adjustment to the source token (“self”):
#   { op: "permanent_add", target_kind: "self", amount: <amount>, destroy_if_zero: false }.
# - Intended to increase (or decrease if amount < 0) a persistent stat (e.g., perm_add/value baseline) that
#   carries over to future spins, independent of the current spin’s temporary steps.
#
# Usage:
# - Attach to a token and set Trigger = ACTIVE_DURING_SPIN.
# - Configure `amount` (positive to grow permanently, negative to shrink).
# - Your executor/CoinManager must implement the command:
#   - op: "permanent_add"
#   - target_kind: "self" (or other targets if you extend this ability)
#   - amount: int
#   - destroy_if_zero: bool (if true and the resulting permanent value hits zero, destroy/replace per your rules)
#
# Notes:
# - This emits a command, not a normal “add/mult” step, so it won’t produce a counting popup unless your executor
#   chooses to display one for permanent changes.
# - If you want reductions to remove the token at zero, set destroy_if_zero = true (and handle guard rules in executor).
# - Define clearly which property you mutate (e.g., t.perm_add or baseline t.value) inside your executor for consistency.

extends TokenAbility
class_name GenericPermanentAddOnActiveAbility

@export var amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN: return []
	return [{"op":"permanent_add","target_kind":"self","amount":amount,"destroy_if_zero":false}]
