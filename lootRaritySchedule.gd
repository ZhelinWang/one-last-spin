extends Resource
class_name LootRaritySchedule

@export var rounds_start: int = 1
@export var rounds_end: int = 19

# Rarity keys expected on tokens (token.get("rarity")).
@export var rarities: PackedStringArray = ["common", "uncommon", "rare", "legendary"]

# Start-of-run target distribution (rounds_start).
@export var start_weights: Array[float] = [0.60, 0.30, 0.09, 0.01]

# End-of-run target distribution (rounds_end).
@export var end_weights: Array[float] = [0.05, 0.40, 0.40, 0.15]

# Normalize per-call to sum to 1.0.
@export var normalize: bool = true

func get_rarity_weights(round_num: int) -> Dictionary:
	# Clamp round and compute t in [0..1]
	var rs: int = max(1, rounds_start)
	var re: int = max(rs, rounds_end)
	var r: int = clamp(round_num, rs, re)
	var denom: float = float(max(1, re - rs))
	var t: float = float(r - rs) / denom

	var out: Dictionary = {}
	var sum: float = 0.0
	var count: int = min(rarities.size(), min(start_weights.size(), end_weights.size()))
	for i in range(count):
		var key: String = String(rarities[i]).to_lower()
		var a: float = float(start_weights[i])
		var b: float = float(end_weights[i])
		var w: float = lerp(a, b, t)
		if w < 0.0:
			w = 0.0
		out[key] = w
		sum += w

	if normalize:
		if sum <= 0.0:
			# Avoid zero-sum: distribute evenly
			var even: float = 1.0 / float(max(1, count))
			for i in range(count):
				out[String(rarities[i]).to_lower()] = even
		else:
			for k in out.keys():
				out[k] = float(out[k]) / sum

	return out

func pick_rarity(round_num: int, rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = get_rarity_weights(round_num)
	# Flatten to arrays for sampling
	var keys: Array[String] = []
	var vals: Array[float] = []
	for k in weights.keys():
		keys.append(String(k))
		vals.append(float(weights[k]))
	# Sample
	var total: float = 0.0
	for v in vals:
		total += max(0.0, v)
	if total <= 0.0:
		return rarities[0] if rarities.size() > 0 else "common"
	var r: float = rng.randf() * total
	var acc: float = 0.0
	for i in range(vals.size()):
		acc += max(0.0, vals[i])
		if r <= acc:
			return keys[i]
	return keys.back()
