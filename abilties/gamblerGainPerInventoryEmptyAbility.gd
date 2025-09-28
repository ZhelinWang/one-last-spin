extends TokenAbility
class_name GamblerGainPerInventoryEmptyAbility

@export var gain_per_empty: int = 10

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var board = ctx.get("board_tokens") if ctx.has("board_tokens") else []
    if not (board is Array):
        return []
    var cnt := 0
    for t in board:
        if t != null and (t as Object).has_method("get") and String(t.get("name")) == "Empty":
            cnt += 1
    if cnt <= 0:
        return []
    return [{"op":"permanent_add","target_kind":"self","amount": int(cnt * gain_per_empty), "destroy_if_zero": false}]

