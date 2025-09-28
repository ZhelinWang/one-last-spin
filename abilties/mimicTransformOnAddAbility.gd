extends TokenAbility
class_name MimicTransformOnAddAbility

## On add: Transform this token into a random token currently in inventory.
@export var exclude_self: bool = true
@export var require_different_name: bool = true

func on_added_to_inventory(board_tokens: Array, ctx: Dictionary, source_token: Resource) -> void:
    if board_tokens == null or not (board_tokens is Array):
        return
    var candidates: Array = []
    for t in board_tokens:
        if t == null or not (t as Object).has_method("get"):
            continue
        if exclude_self and t == source_token:
            continue
        if require_different_name:
            var n1 := String(source_token.get("name")) if source_token.has_method("get") else ""
            var n2 := String(t.get("name"))
            if n1 == n2:
                continue
        candidates.append(t)
    if candidates.is_empty():
        return
    var rng: RandomNumberGenerator = ctx.get("rng") if ctx.has("rng") else RandomNumberGenerator.new()
    if not ctx.has("rng"):
        rng.randomize()
    var pick = candidates[rng.randi_range(0, candidates.size()-1)]
    if pick == null:
        return
    var sr = ctx.get("spin_root") if ctx.has("spin_root") else null
    if sr != null and (sr as Object).has_method("replace_token_in_inventory"):
        sr.call("replace_token_in_inventory", source_token, pick)

