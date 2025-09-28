extends TokenAbility
class_name MarkedCardsPairDoubleAbility

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    var out: Array = []
    var self_c := _find_self_contrib(contribs, source_token)
    if self_c.is_empty():
        return out
    var self_val := _contrib_value(self_c)
    for nc in _adjacent_contribs(contribs, self_c):
        var tok = nc.get("token")
        if tok != null and (tok as Object).has_method("get") and String(tok.get("name")) == "Marked Card":
            var nval := _contrib_value(nc)
            out.append({"op":"permanent_add","target_kind":"self","amount": int(self_val),"destroy_if_zero": false})
            out.append({"op":"permanent_add","target_kind":"offset","target_offset": int(nc.get("offset", 0)), "amount": int(nval),"destroy_if_zero": false})
            break
    return out

