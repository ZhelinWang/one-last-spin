extends TokenAbility
class_name DestroyTriggeredEmptiesAbility

func _init():
	winner_only = true
	trigger = Trigger.ACTIVE_DURING_SPIN

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	var commands: Array = []
	for c in contribs:
		if not (c is Dictionary):
			continue
		var tok = c.get("token")
		if tok == null:
			continue
		if String(tok.get("name")) != "Empty":
			continue
		commands.append({"op": "destroy", "target_offset": int(c.get("offset", 0))})
	return commands
