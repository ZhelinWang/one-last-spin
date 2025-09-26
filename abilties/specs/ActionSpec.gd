extends Resource
class_name AbilityAction

# Declarative action to perform when conditions (from EffectSpec and/or local) pass.
# Supported ops:
# - "add"                   -> spin step: +amount
# - "mult"                  -> spin step: x factor
# - "permanent_add"         -> command: adjust inventory offsets (persistent)
# - "replace"               -> command: replace token(s)
# - "destroy"               -> command: destroy target (replace with empty)
# - "adjust_run_total"      -> command: modify run total coins immediately

## What the action does.
## - add: temporary +amount to value this spin
## - mult: temporary x factor to value this spin
## - permanent_add: permanent adjustment to token base values in inventory
## - replace: replace tokens (by offset/tag/any) with another resource
## - destroy: destroy target token (replaces with Empty)
## - adjust_run_total: modify the run total coins immediately
@export var op: String = "add"

# Common numeric parameters
## For add/permanent_add/adjust_run_total: the amount to add/subtract.
@export var amount: int = 0

## For mult: the multiplier factor (e.g., 2.0 doubles value).
@export var factor: float = 1.0

# Description override for UI/log
## Optional UI text. Supports %d (amount), %f (factor), %s (source name).
@export var desc_template: String = ""

# Optional local conditions for this action
## Extra conditions for this action (in addition to EffectSpec conditions).
@export var conditions: Array[AbilityCondition] = []

# Optional per-action targeting override. If empty, EffectSpec/TokenAbility targeting is used.
# Examples: "self", "neighbors", "offset", "tag", "name", "left", "right", "edges", "any", "active", "passive".
## Optional per-action target override. If blank, EffectSpec/TokenAbility target is used.
@export var target_override_kind: String = ""

## For target_override_kind == "offset": relative slot (-2..2).
@export var target_offset: int = 0

## For target_override_kind == "tag": tag to match.
@export var target_tag: String = ""

## For target_override_kind == "name": exact token name to match.
@export var target_name: String = ""

# Replace specifics
## For op == "replace": path to the replacement token resource (e.g., res://tokens/coin.tres).
@export var token_path: String = ""

## For replace: if true, copy tags from removed token to new one.
@export var preserve_tags: bool = false

## For replace: if true, seed replacement token's value from `amount`.
@export var set_value_from_amount: bool = false

# Permanent add specifics
## For permanent_add: if true, destroy tokens that drop below 1 permanently.
@export var destroy_if_zero: bool = false

## For permanent_add targeting self/offset: also apply to all tokens with the same internal key ("same copies").
@export var propagate_same_key: bool = false
