extends TokenAbility
class_name ReplaceTargetByRarityAbility

## Active (target): Replace the target with a random token promoted/demoted by rarity.
## mode: "promote" or "demote"
@export var mode: String = "demote"
@export var tokens_root: String = "res://tokens"
@export var exclude_names: PackedStringArray = ["Empty"]

const ORDER := ["common", "uncommon", "rare", "legendary"]

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func _rarity_index(r: String) -> int:
	var rr := r.strip_edges().to_lower()
	for i in range(ORDER.size()):
		if ORDER[i] == rr:
			return i
	return -1

func _list_token_paths() -> Array[String]:
	var out: Array[String] = []
	var da = DirAccess.open(tokens_root)
	if da == null:
		return out
	var files = da.get_files()
	for f in files:
		if not f.ends_with(".tres"):
			continue
		out.append(tokens_root.path_join(f))
	return out

func _pick_path_for_rarity(rr: String) -> String:
	var candidates: Array[String] = []
	for p in _list_token_paths():
		var res = ResourceLoader.load(p)
		if res == null or not (res as Object).has_method("get"):
			continue
		var nm = String(res.get("name"))
		if exclude_names.has(nm):
			continue
		if String(res.get("rarity")).to_lower() == rr:
			candidates.append(p)
	if candidates.is_empty():
		return ""
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return candidates[rng.randi_range(0, candidates.size()-1)]

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var out: Array = []
	# Defer target selection and rarity computation to executor to support interactive pick.
	out.append({
		"op": "replace_by_rarity_step",
		"target_kind": "choose",
		"mode": String(mode),
		"tokens_root": tokens_root
	})
	return out
