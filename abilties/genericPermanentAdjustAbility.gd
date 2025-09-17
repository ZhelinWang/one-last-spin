# GenericPermanentAdjustAbility
# Effect:
# - During Active During Spin, emits one or more commands to permanently adjust token stats:
#   { op: "permanent_add", amount: <int>, destroy_if_zero: <bool>, target_* per selection }.
# - By default targets according to the ability’s target_kind/target_offset/tag/name.
# - If exclude_self = true, targets all current spin contribs except the source (emits per-offset commands).
#
# Usage:
# - Attach to a token; set Trigger = ACTIVE_DURING_SPIN.
# - Configure:
#   - amount: permanent delta (negative to shrink, positive to grow).
#   - destroy_if_zero: if true, executor should remove/replace a token when its permanent stat reaches zero.
#   - exclude_self: when true, ignore the source and apply to others in the current 5-slot contrib set.
#   - target_kind/target_offset/target_tag/target_name: selection used when exclude_self is false.
#
# Executor requirements:
# - Implement command:
#   op: "permanent_add", fields:
#     - target_kind: "self" | "offset" | "tag" | "name" | "any" (matches TokenAbility _tk_to_string()).
#     - target_offset/target_tag/target_name as needed.
#     - amount: int, destroy_if_zero: bool.
# - Apply guard rules if present (e.g., guard aura may block destruction).
#
# Notes:
# - Exclude-self mode iterates current contribs only; use target_kind-based mode for broader selection.
# - Visual feedback is executor-defined (permanent changes don’t automatically create popups).

extends TokenAbility
class_name GenericPermanentAdjustAbility

@export var amount: int = -1
@export var destroy_if_zero: bool = true
@export var exclude_self: bool = false
@export var propagate_same_key: bool = false

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN: return []
	var cmds: Array = []
	if exclude_self:
		var self_c := _find_self_contrib(contribs, source_token)
		for c in contribs:
			if c == self_c:
				continue
			var cmd := {"op":"permanent_add","target_kind":"offset","target_offset":int(c.get("offset",0)),"amount":amount,"destroy_if_zero":destroy_if_zero}
			if propagate_same_key:
				cmd["propagate_same_key"] = true
			cmds.append(cmd)
	else:
		var cmd := {"op":"permanent_add","target_kind":_tk_to_string(),"target_offset":target_offset,"target_tag":target_tag,"target_name":target_name,"amount":amount,"destroy_if_zero":destroy_if_zero}
		if propagate_same_key:
			cmd["propagate_same_key"] = true
		cmds.append(cmd)
	return cmds
