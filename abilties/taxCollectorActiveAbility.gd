extends TokenAbility
class_name TaxCollectorActiveAbility

## Maximum amount to steal from each other triggered token (never reduces below 1 during steal).
@export var steal_amount: int = 2

## Permanent gain applied to self each time the active triggers.
@export var self_permanent_gain: int = 4

## Permanent bonus awarded to all Coin tokens each time the active triggers.
@export var coin_permanent_bonus: int = 2

## If true, skip targets that currently have final value <= 0 (prevents stealing from zeros).
@export var require_positive_targets: bool = true

func _source_id() -> String:
	var sid: String = id if typeof(id) == TYPE_STRING else ""
	sid = sid.strip_edges()
	if sid == "":
		sid = "TaxCollectorActive"
	return "ability:%s" % sid

func _collect_target_entries(contribs: Array, self_c: Dictionary, max_deduct: int) -> Dictionary:
	var entries: Array[Dictionary] = []
	var total: int = 0
	if max_deduct <= 0:
		return {"entries": entries, "total": total}
	for raw in contribs:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		if c == self_c:
			continue
		var kind: String = String(c.get("kind", "")).to_lower()
		if kind != "active" and kind != "passive":
			continue
		if require_positive_targets and _contrib_value(c) <= 0:
			continue
		var off: int = int(c.get("offset", 0))
		var value: int = max(0, _contrib_value(c))
		if value <= 0:
			continue
		var safe_remaining: int = max(value - 1, 0)
		var deduct: int = min(max_deduct, safe_remaining)
		if deduct <= 0:
			continue
		entries.append({"offset": off, "deduct": deduct})
		total += deduct
	return {"entries": entries, "total": total}

func _build_steal_steps(src: String, entries: Array[Dictionary]) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for entry in entries:
		var off: int = int(entry.get("offset", 0))
		var deduct: int = int(entry.get("deduct", 0))
		if deduct <= 0:
			continue
		steps.append({
			"kind": "final_add",
			"amount": -deduct,
			"desc": "Tax Collector steals %d" % deduct,
			"source": src,
			"target_kind": "offset",
			"target_offset": off,
			"min_value": 1
		})
	return steps


func _build_gain_step(src: String, amount: int) -> Dictionary:
	return {
		"kind": "add",
		"amount": amount,
		"factor": 1.0,
		"desc": "Tax Collector gains %d" % amount,
		"source": src,
		"target_kind": "self",
		"target_offset": 0
	}

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c: Dictionary = _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var max_deduct: int = max(0, steal_amount)
	if max_deduct <= 0:
		return []
	var src: String = _source_id()
	var info: Dictionary = _collect_target_entries(contribs, self_c, max_deduct)
	var entries_var = info.get("entries", [])
	var entries: Array[Dictionary] = []
	if entries_var is Array:
		for item in entries_var:
			if item is Dictionary:
				entries.append(item)
	var steps: Array[Dictionary] = _build_steal_steps(src, entries)
	return steps

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	if trigger != Trigger.ACTIVE_DURING_SPIN:
		return []
	var self_c: Dictionary = _find_self_contrib(contribs, source_token)
	if self_c.is_empty():
		return []
	var commands: Array[Dictionary] = []
	var self_gain: int = max(0, self_permanent_gain)
	if self_gain > 0:
		commands.append({
			"op": "permanent_add",
			"target_kind": "self",
			"target_offset": 0,
			"amount": self_gain,
			"destroy_if_zero": false,
			"propagate_same_key": true
		})
	var coin_gain: int = max(0, coin_permanent_bonus)
	if coin_gain > 0:
		commands.append({
			"op": "permanent_add",
			"target_kind": "tag",
			"target_tag": "coin",
			"amount": coin_gain,
			"destroy_if_zero": false,
			"propagate_same_key": true
		})
	return commands
