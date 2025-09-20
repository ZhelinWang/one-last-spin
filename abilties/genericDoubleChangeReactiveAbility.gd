# GenericDoubleChangeReactiveAbility
# Doubles any per-spin value change applied to the token that owns this ability.
# Guards ensure we only react once per step even if the engine reports multiple value-change events.

extends TokenAbility
class_name GenericDoubleChangeReactiveAbility

@export var multiplier: float = 2.0

var _owner_token: Resource = null

func on_value_changed(ctx: Dictionary, prev_val: int, new_val: int, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}, step: Dictionary = {}) -> void:
	if not _ensure_owner(target_token):
		return
	if not (target_contrib is Dictionary):
		return

	var delta := new_val - prev_val
	if delta == 0:
		return

	var processed = target_contrib.get("__dc_processed", {})
	if not (processed is Dictionary):
		processed = {}
	var owner_id: int = _owner_instance_id()
	var key := _build_event_key(owner_id, prev_val, new_val, step)
	if key != "" and bool(processed.get(key, false)):
		return

	var extra := int(round(float(delta) * (max(multiplier, 0.0) - 1.0)))
	if extra == 0:
		return

	target_contrib["delta"] = int(target_contrib.get("delta", 0)) + extra

	if key != "":
		processed[key] = true
		target_contrib["__dc_processed"] = processed

func _ensure_owner(target_token) -> bool:
	if target_token == null or not target_token.has_method("get"):
		return false
	if _owner_token != null and target_token == _owner_token:
		return true
	var abilities = target_token.get("abilities")
	if abilities is Array:
		for ab in abilities:
			if ab == self:
				_owner_token = target_token
				return true
	if _owner_token != null and _owner_token.has_method("get"):
		var cached_name = _owner_token.get("name") if _owner_token.has_method("get") else ""
		var target_name = target_token.get("name")
		if typeof(cached_name) == TYPE_STRING and typeof(target_name) == TYPE_STRING and String(cached_name) == String(target_name):
			_owner_token = target_token
			return true
	return false

func _owner_instance_id() -> int:
	if _owner_token == null:
		return 0
	if _owner_token.has_method("get_instance_id"):
		return int(_owner_token.get_instance_id())
	return 0
func _build_event_key(owner_id: int, prev_val: int, new_val: int, step: Dictionary) -> String:
	var src := ""
	var kind := ""
	if step is Dictionary:
		src = String(step.get("source", ""))
		kind = String(step.get("kind", ""))
	return "%d|%d|%d|%s|%s" % [owner_id, prev_val, new_val, src, kind]
