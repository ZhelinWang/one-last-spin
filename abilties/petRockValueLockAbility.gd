extends TokenAbility
class_name PetRockValueLockAbility

const LOCK_KEY := "__pet_rock_locking"

func filter_step(ctx: Dictionary, step: Dictionary, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}) -> Variant:
	# Only act when this ability belongs to the target token (i.e., Pet Rock is the target).
	var is_target_side := false
	if target_token != null and (target_token as Object).has_method("get"):
		var abilities = target_token.get("abilities")
		if abilities is Array and (abilities as Array).has(self):
			is_target_side = true
	if not is_target_side:
		return step

	# Cancel any value-changing step applied to Pet Rock (add/mult/final_add).
	var kind := String(step.get("kind", "")).to_lower()
	if kind == "add" or kind == "mult" or kind == "final_add":
		return null
	return step

func on_value_changed(ctx: Dictionary, prev_val: int, new_val: int, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}, step: Dictionary = {}) -> void:
	# Only react when this ability belongs to the target token (Pet Rock itself).
	if target_token == null or not (target_token as Object).has_method("get"):
		return
	var abilities = target_token.get("abilities")
	if not (abilities is Array and (abilities as Array).has(self)):
		return

	if prev_val == new_val:
		return
	if ctx == null:
		return
	if bool(ctx.get(LOCK_KEY, false)):
		ctx[LOCK_KEY] = false
		return
	ctx[LOCK_KEY] = true

	# Revert Pet Rock to its previous value and reset contrib state.
	if (target_token as Object).has_method("set"):
		target_token.set("value", prev_val)
	if target_contrib is Dictionary and not target_contrib.is_empty():
		target_contrib["base"] = prev_val
		target_contrib["delta"] = 0
		target_contrib["mult"] = 1.0
		var force_var: Variant = ctx.get("__force_value_sync_offsets", null)
		var force_offsets: Array = []
		if force_var is Array:
			force_offsets = (force_var as Array).duplicate()
		var off: int = int(target_contrib.get("offset", 0))
		if not force_offsets.has(off):
			force_offsets.append(off)
		ctx["__force_value_sync_offsets"] = force_offsets
