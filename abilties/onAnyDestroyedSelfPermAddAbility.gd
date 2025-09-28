extends TokenAbility
class_name OnAnyDestroyedSelfPermAddAbility

@export var amount: int = 1

func on_any_token_destroyed(ctx: Dictionary, destroyed_token: Resource, source_token: Resource) -> Array:
    if amount == 0:
        return []
    return [{"op":"permanent_add","target_kind":"self","amount": int(amount),"destroy_if_zero": false}]

