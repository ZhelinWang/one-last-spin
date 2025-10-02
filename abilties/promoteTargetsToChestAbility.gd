extends TokenAbility
class_name PromoteTargetsToChestAbility

@export var chest_path: String = "res://tokens/TreasureHunters/smallChest.tres"
@export var chest_paths: PackedStringArray = PackedStringArray([
	"res://tokens/TreasureHunters/smallChest.tres",
	"res://tokens/TreasureHunters/goldenChest.tres"
])
@export var count: int = 2

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func _pick_chest_path(rng: RandomNumberGenerator) -> String:
	var candidates: Array[String] = []
	for p in chest_paths:
		var path_s := String(p).strip_edges()
		if path_s != "":
			candidates.append(path_s)
	if candidates.is_empty():
		var fallback := String(chest_path).strip_edges()
		if fallback != "":
			candidates.append(fallback)
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var out: Array = []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	for i in range(max(1, count)):
		var path_choice := _pick_chest_path(rng)
		if path_choice == "":
			continue
		out.append({
			"op": "replace_at_offset",
			"token_path": path_choice,
			"set_value": -1,
			"preserve_tags": false,
			"target_kind": "choose"
		})
	return out
