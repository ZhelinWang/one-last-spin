extends TokenAbility
class_name GenericMultiplyAbility

## Temporary multiplier to apply (e.g., 2.0 doubles the value) to the selected target(s).
@export var factor: float = 2.0

func _resolve_desc(source_token: Resource) -> String:
	var template := desc_template
	if template.strip_edges() == "":
		template = "x%s buff from %s"
	return template % [factor, _token_name(source_token)]

func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	# Only self during per-token phase; broadcast handled in final phase if Target != SELF
	if target_kind != TokenAbility.TargetKind.SELF:
		return []
	if not matches_target(ctx, contrib, source_token):
		return []
	return [_mk_mult_step(factor, _resolve_desc(source_token), "ability:%s" % id)]

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN or target_kind == TokenAbility.TargetKind.SELF:
		return []
	return [make_global_step("mult", 0, factor, _resolve_desc(source_token), "ability:%s" % id)]

func should_refresh_after_board_change() -> bool:
	return true
