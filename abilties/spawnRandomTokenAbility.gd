extends TokenAbility
class_name SpawnRandomTokenAbility

@export var tokens_root: String = "res://tokens"
@export var exclude_names: PackedStringArray = PackedStringArray(["Empty", "empty"])
@export var count: int = 1

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func _collect_token_paths(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			if name.begins_with("."):
				continue
			out.append_array(_collect_token_paths(root.path_join(name)))
		else:
			if name.ends_with(".tres") or name.ends_with(".res"):
				out.append(root.path_join(name))
	dir.list_dir_end()
	return out

func _is_excluded(path: String) -> bool:
	var base := String(path.get_file().get_basename())
	var base_lower := base.to_lower()
	for name in exclude_names:
		var n := String(name)
		if n == base or n.to_lower() == base_lower:
			return true
	return false

func _pick_paths(rng: RandomNumberGenerator, available: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var pool: Array[String] = []
	for path in available:
		if _is_excluded(path):
			continue
		pool.append(path)
	for i in range(max(1, count)):
		if pool.is_empty():
			break
		var pick := pool[rng.randi_range(0, pool.size() - 1)]
		out.append(pick)
	return out

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
		return []
	var paths := _collect_token_paths(tokens_root)
	if paths.is_empty():
		return []
	var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
	if not ctx.has("rng"):
		rng.randomize()
	var picks := _pick_paths(rng, paths)
	var commands: Array = []
	for path in picks:
		commands.append({"op": "spawn_token_in_inventory", "token_path": path, "count": 1})
	return commands
