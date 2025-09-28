extends TokenAbility
class_name TreasureRatAbility

@export var worn_map_path: String = "res://tokens/TreasureHunters/wornMap.tres"
@export var chest_path: String = "res://tokens/TreasureHunters/smallChest.tres"
@export var spawn_chance: float = 0.25

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var out: Array = []
    # Active: target to Worn Map
    out.append({"op":"replace_at_offset","offset": 0, "token_path": String(worn_map_path), "set_value": -1, "preserve_tags": false, "target_kind":"choose"})
    # Passive: 25% spawn a Chest if adjacent to Empty
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return out
    var has_empty_adj := false
    for nc in _adjacent_contribs(contribs, self_c):
        var tok = nc.get("token")
        if tok != null and (tok as Object).has_method("get") and String(tok.get("name")) == "Empty":
            has_empty_adj = true
            break
    if has_empty_adj:
        var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
        if not ctx.has("rng"): rng.randomize()
        if rng.randf() <= max(0.0, min(1.0, float(spawn_chance))):
            out.append({"op":"spawn_token_in_inventory","token_path": String(chest_path), "count": 1})
    return out



