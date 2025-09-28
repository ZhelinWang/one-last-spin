extends TokenAbility
class_name MastermindOnRemovedPromoteKillerAbility

@export var mastermind_path: String = "res://tokens/Villains/mastermind.tres"

func build_on_removed_commands(ctx: Dictionary, removed_token: Resource, source_token: Resource) -> Array:
    var out: Array = []
    var killer = null
    if ctx is Dictionary and ctx.has("destroyed_by_token"):
        killer = ctx["destroyed_by_token"]
    if killer == null:
        return out
    var p := String(mastermind_path).strip_edges()
    if p == "":
        return out
    out.append({"op":"promote_token_in_inventory", "from_ref": killer, "token_path": p})
    return out



