extends TokenAbility
class_name ReplaceTargetWithSelfCopyAbility

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    var path := ""
    if source_token is Resource:
        var rp := (source_token as Resource).resource_path
        if rp != null:
            path = String(rp)
    if path.strip_edges() == "":
        return []
    return [{"op":"replace_at_offset","offset": 0, "token_path": path, "set_value": -1, "preserve_tags": false, "target_kind":"choose"}]

