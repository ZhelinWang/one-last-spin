extends TokenAbility
class_name DestroySelfOnLossAbility

func on_value_changed(ctx: Dictionary, prev_val: int, new_val: int, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}, step: Dictionary = {}) -> void:
    if target_token != source_token:
        return
    if new_val >= prev_val:
        return
    var self_off := 0
    if target_contrib is Dictionary:
        self_off = int(target_contrib.get("offset", 0))
    var pend = ctx.get("__pending_commands", [])
    if not (pend is Array):
        pend = []
    (pend as Array).append({"op":"destroy", "target_offset": self_off})
    ctx["__pending_commands"] = pend

