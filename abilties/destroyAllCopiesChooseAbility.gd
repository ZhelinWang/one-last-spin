extends TokenAbility
class_name DestroyAllCopiesChooseAbility

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    return [{"op":"destroy_all_copies_choose", "target_kind":"choose"}]

