extends TokenAbility
class_name RookieAdjacentHigherGainAbility

@export var amount: int = 1

func _should_gain(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> bool:
	if contrib == null or contrib.is_empty():
		return false

	# Pull contribs from ctx safely and type them.
	var contribs_variant: Variant = (ctx.get("__last_contribs") if (ctx is Dictionary) else [])
	var contribs: Array = (contribs_variant if (contribs_variant is Array) else [])

	if contribs.is_empty():
		contribs = [contrib]

	var neighbors: Array = _adjacent_contribs(contribs, contrib)
	if neighbors.is_empty():
		return false

	var self_val: int = int(_contrib_value(contrib))
	for nc in neighbors:
		if (nc is Dictionary) and int(_contrib_value(nc)) > self_val:
			return true
	return false


func _apply_permanent_gain(ctx: Dictionary, source_token: Resource) -> void:
	if source_token == null or not (source_token as Object).has_method("set"):
		return

	var has_spin: bool = (ctx is Dictionary) and ctx.has("spin_index")
	var spin_idx: int = (int(ctx["spin_index"]) if has_spin else -1)

	var last_spin: int = -999_999
	if (source_token as Object).has_method("has_meta") and source_token.has_meta("__rookie_last_spin_gain"):
		last_spin = int(source_token.get_meta("__rookie_last_spin_gain"))

	# Already granted this spin?
	if has_spin and spin_idx == last_spin:
		return

	var current: int = 0
	if (source_token as Object).has_method("get"):
		var v: Variant = source_token.get("value")
		if v != null:
			current = int(v)

	source_token.set("value", current + amount)

	if (source_token as Object).has_method("set_meta"):
		source_token.set_meta("__rookie_last_spin_gain", spin_idx)
		source_token.set_meta("base_value", current + amount)

	# Try to refresh any cached baselines on a spin root, if present.
	var sr: Variant = (ctx.get("spin_root") if ((ctx is Dictionary) and ctx.has("spin_root")) else null)
	if sr != null and is_instance_valid(sr):
		if (sr as Object).has_method("_refresh_inventory_baseline"):
			sr.call_deferred("_refresh_inventory_baseline")


func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN:
		return []
	if not _should_gain(ctx, contrib, source_token):
		return []

	_apply_permanent_gain(ctx, source_token)

	var desc: String = ""
	if typeof(desc_template) == TYPE_STRING:
		desc = String(desc_template).strip_edges()
		if desc.find("%d") != -1:
			desc = desc % amount
	if desc == "":
		desc = "+%d" % amount

	var step: Dictionary = _mk_add_step(int(amount), desc, "ability:%s" % id)
	return [step]


func should_refresh_after_board_change() -> bool:
	return true
