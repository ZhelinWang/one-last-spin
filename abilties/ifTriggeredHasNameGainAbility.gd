extends TokenAbility
class_name IfTriggeredHasNameGainAbility

@export var name_to_check: String = "Empty"
@export var amount: int = 1

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    for c in contribs:
        if c is Dictionary:
            var tok = (c as Dictionary).get("token")
            if tok != null and (tok as Object).has_method("get") and String(tok.get("name")) == name_to_check:
                return [{"op":"permanent_add","target_kind":"self","amount": int(amount), "destroy_if_zero": false}]
    return []

