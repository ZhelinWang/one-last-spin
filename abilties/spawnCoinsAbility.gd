extends TokenAbility
class_name SpawnCoinsAbility

@export var count: int = 2
@export var coin_path: String = "res://tokens/Hoarder/coin.tres"

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    return [{"op":"spawn_token_in_inventory","token_path": String(coin_path), "count": int(max(1, count))}]



