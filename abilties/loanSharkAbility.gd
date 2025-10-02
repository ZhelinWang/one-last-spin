extends TokenAbility
class_name LoanSharkAbility

@export var coin_paths: PackedStringArray = PackedStringArray([
	"res://tokens/Hoarder/coin.tres",
	"res://tokens/Hoarder/copperCoin.tres",
	"res://tokens/TreasureHunters/rustedCoin.tres"
])

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func _pick_coin_path(rng: RandomNumberGenerator) -> String:
	var options: Array[String] = []
	for p in coin_paths:
		var ps := String(p).strip_edges()
		if ps != "":
			options.append(ps)
	if options.is_empty():
		return "res://tokens/Hoarder/coin.tres"
	return options[rng.randi_range(0, options.size() - 1)]

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c := _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var adj := _adjacent_contribs(contribs, self_c)
	var victims: Array[Dictionary] = []
	for c in adj:
		if not (c is Dictionary):
			continue
		var tok = c.get("token")
		if tok == null:
			continue
		if String(tok.get("name")) == "Empty":
			continue
		victims.append(c)
	if victims.is_empty():
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var pick: Dictionary = victims[rng.randi_range(0, victims.size() - 1)]
	var off := int(pick.get("offset", 0))
	var commands: Array = []
	commands.append({"op": "destroy", "target_offset": off})
	commands.append({
		"op": "spawn_token_in_inventory",
		"token_path": _pick_coin_path(rng),
		"count": 1
	})
	return commands
