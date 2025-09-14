extends TokenAbility
class_name GenericSetFromContextAbility

enum Compute { PERCENT_OF_BANK }
@export var compute: Compute = Compute.PERCENT_OF_BANK
@export var percent: float = 0.10  # for PERCENT_OF_BANK

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN: return []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty(): return []
	var cur := _contrib_value(self_c)
	var target := cur
	match compute:
		Compute.PERCENT_OF_BANK:
			var bank: int = int(ctx.get("run_total", 0))
			target = int(floor(max(0.0, float(bank)) * max(percent, 0.0)))
	var delta := target - cur
	if delta == 0: return []
	return [mk_global_step("add", delta, 1.0, "Set value", "ability:%s"%id)]
