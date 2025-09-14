extends TokenAbility
class_name GenericAddAbility

@export var amount: int = 1

func _desc_or_default(src_name: String) -> String:
	var tpl := String(desc_template)
	if tpl.strip_edges() == "":
		return "+%d from %s" % [amount, src_name]
	# Allow %d or %s placeholders (safe-ish)
	if tpl.find("%d") != -1 and tpl.find("%s") != -1:
		return tpl % [amount, src_name]
	if tpl.find("%d") != -1:
		return tpl % [amount]
	if tpl.find("%s") != -1:
		return tpl % [src_name]
	return tpl

# Per-token phase
func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	# Gate by target_kind/winner_only via base helper
	if not matches_target(ctx, contrib, source_token):
		return []
	if amount == 0:
		return []
	var src_name := _token_name(source_token)
	return [_mk_add_step(amount, _desc_or_default(src_name), "ability:%s" % id)]

# Winner final/global phase (non-self targets)
func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	# If this ability is authored to affect non-self targets (e.g., neighbors, tag),
	# emit a global step; CoinManager will route it using target_* fields.
	if target_kind == TokenAbility.TargetKind.SELF:
		return []
	if amount == 0:
		return []
	var src_name := _token_name(source_token)
	return [make_global_step("add", amount, 1.0, _desc_or_default(src_name), "ability:%s" % id)]
