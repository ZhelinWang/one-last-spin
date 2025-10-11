extends TokenAbility
class_name AddToAdjacentWithTagAbility

## Add a flat amount to adjacent neighbors that have a required tag (case-insensitive) during spin.
@export var amount: int = 1
@export var required_tag: String = "human"
@export var desc: String = "+%d to adjacent %s"

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    if amount == 0:
        return []
    var out: Array = []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return out
    var tag_l := String(required_tag).strip_edges().to_lower()
    var src_name := _token_name(source_token)
    for nc in _adjacent_contribs(contribs, self_c):
        var tok = nc.get("token")
        if _token_has_tag(tok, tag_l):
            var off := int(nc.get("offset", 0))
            var d := desc
            if d.find("%d") != -1 and d.find("%s") != -1:
                d = d % [amount, required_tag]
            elif d.find("%d") != -1:
                d = d % [amount]
            elif d.find("%s") != -1:
                d = d % [required_tag]
            out.append({
                "kind": "add",
                "amount": amount,
                "factor": 1.0,
                "desc": d,
                "source": "ability:%s" % str(id),
                "target_kind": "offset",
                "target_offset": off
            })
    return out

func should_refresh_after_board_change() -> bool:
    # Adjacency depends on neighbors; re-evaluate when the board changes mid-spin.
    return true
