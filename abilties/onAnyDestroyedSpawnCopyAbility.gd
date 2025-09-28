extends TokenAbility
class_name OnAnyDestroyedSpawnCopyAbility

## On any token destroyed, add a copy of it to inventory (fills an Empty if possible).

func on_any_token_destroyed(ctx: Dictionary, destroyed_token: Resource, source_token: Resource) -> Array:
    if destroyed_token == null:
        return []
    return [{"op":"spawn_copy_in_inventory", "token_ref": destroyed_token}]

