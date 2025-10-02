extends TokenAbility
class_name SpawnCoinsAbility

@export var count: int = 2
@export var coin_path: String = "res://tokens/Hoarder/coin.tres"
@export var coin_paths: PackedStringArray = PackedStringArray([])

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func _pick_path(rng: RandomNumberGenerator) -> String:
	var options: Array[String] = []
	for p in coin_paths:
		var ps := String(p).strip_edges()
		if ps != "":
			options.append(ps)
	if options.is_empty():
		var fallback := String(coin_path).strip_edges()
		if fallback != "":
			options.append(fallback)
	if options.is_empty():
		return "res://tokens/Hoarder/coin.tres"
	return options[rng.randi_range(0, options.size() - 1)]

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var commands: Array = []
	for i in range(max(1, count)):
		commands.append({"op":"spawn_token_in_inventory","token_path": _pick_path(rng), "count": 1})
	return commands
