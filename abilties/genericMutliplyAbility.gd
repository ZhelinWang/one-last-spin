extends TokenAbility
class_name GenericMultiplyAbility

@export var factor: float = 2.0

func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	# Only self during per-token phase; broadcast handled in final phase if Target != SELF
	if target_kind != TokenAbility.TargetKind.SELF:
		return []
	if not matches_target(ctx, contrib, source_token):
		return []
	var src_name := _token_name(source_token)
	return [_mk_mult_step(factor, desc_template % [factor, src_name], "ability:%s" % id)]

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN or target_kind == TokenAbility.TargetKind.SELF:
		return []
	var src_name := _token_name(source_token)
	return [make_global_step("mult", 0, factor, desc_template % [factor, src_name], "ability:%s" % id)]
