extends TokenAbility
class_name DestroyTargetAndGainValueAbility

## Active (target): Destroy the target and gain a portion of its value permanently.
@export var gain_fraction_numer: int = 1
@export var gain_fraction_denom: int = 2
@export var also_replace_with_path: String = ""  ## e.g., res://tokens/coin.tres
@export var replacement_paths: PackedStringArray = PackedStringArray([])

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func _pick_replacement_path(rng: RandomNumberGenerator) -> String:
	var options: Array[String] = []
	for p in replacement_paths:
		var ps := String(p).strip_edges()
		if ps != "":
			options.append(ps)
	if options.is_empty():
		var fallback := String(also_replace_with_path).strip_edges()
		if fallback != "":
			options.append(fallback)
	if options.is_empty():
		return ""
	return options[rng.randi_range(0, options.size() - 1)]

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var replace_path := _pick_replacement_path(rng)
	var out: Array = []
	out.append({
		"op": "destroy_and_gain_fraction",
		"target_kind": "choose",
		"gain_numer": int(gain_fraction_numer),
		"gain_denom": int(max(1, gain_fraction_denom)),
		"replace_path": replace_path
	})
	return out
