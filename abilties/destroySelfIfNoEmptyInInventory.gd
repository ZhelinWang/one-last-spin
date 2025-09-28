extends TokenAbility
class_name DestroySelfIfNoEmptyInInventory

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var board = ctx.get("board_tokens") if ctx.has("board_tokens") else []
    if not (board is Array):
        return []
    var has_empty := false
    for t in board:
        if t != null and (t as Object).has_method("get") and String(t.get("name")) == "Empty":
            has_empty = true
            break
    if has_empty:
        return []
    var self_c := _find_self_contrib(contribs, source_token)
    var off := 0
    if not self_c.is_empty(): off = int(self_c.get("offset", 0))
    return [{"op":"destroy", "target_offset": off}]

