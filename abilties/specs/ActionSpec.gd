extends Resource
class_name AbilityAction

# Declarative action to perform when conditions (from EffectSpec and/or local) pass.
# Supported ops:
# - "add"                        -> spin step: +amount
# - "mult"                       -> spin step: x factor
# - "permanent_add"              -> command: adjust inventory offsets (persistent)
# - "replace"                    -> command: replace token(s)
# - "destroy"                    -> command: destroy target (replace with empty)
# - "adjust_run_total"           -> command: modify the run total coins immediately
# - "reroll_same_rarity"         -> command: reroll target with token of same rarity
# - "replace_by_rarity"          -> command: replace target with token demoted/promoted in rarity
# - "spawn_token_in_inventory"   -> command: spawn token(s) into inventory (path-based)
# - "adjust_empty_rarity_bonus"  -> command: adjust global Empty rarity bonus
# - "guarantee_next_loot_rarity" -> command: guarantee next loot rarity
# - "add_loot_options_bonus"     -> command: increase next loot options count
# - "restart_round"              -> command: restart current round

## What the action does. Use the dropdown for clarity in the editor.
@export_enum(
    "Add Value: add",
    "Multiply Value: mult",
    "Add Permanent Value: permanent_add",
    "Replace Token: replace",
    "Destroy Token: destroy",
    "Adjust Player Total: adjust_run_total",
    "Reroll Same Rarity: reroll_same_rarity",
    "Replace With Rarity Change: replace_by_rarity",
    "Spawn Token(s) To Inventory: spawn_token_in_inventory",
    "Spawn Random (Any): spawn_random_any",
    "Adjust Empty Rarity Bonus: adjust_empty_rarity_bonus",
    "Guarantee Next Loot Rarity: guarantee_next_loot_rarity",
    "Increase Loot Options: add_loot_options_bonus",
    "Restart Round: restart_round",
    "Set Perm To Value: set_perm_to_value",
    "Set Target Perm To Self Current: set_perm_to_self_current",
    "Set Self Perm To Target Current: set_self_perm_to_target_current",
    "Double Target Permanent: double_target_permanent",
    "Destroy And Gain Fraction: destroy_and_gain_fraction",
    "Replace Target With Self Copy: replace_target_with_self_copy",
    "Replace Self With Random Inventory: replace_self_with_random_inventory",
    "Destroy All Copies (Choose Target): destroy_all_copies_choose",
    "Mastermind Destroy Target And Buff: mastermind_destroy_target_and_buff",
    "Permanent Add From Last Destroyed: permanent_add_from_last_destroyed",
    "Add From Self Current: add_from_self_current",
    "Permanent Add By Inventory Count: permanent_add_by_inventory_count",
    "Destroy All Copies By Name: destroy_all_copies_by_name",
    "Spawn Copy Of Last Destroyed: spawn_copy_of_last_destroyed",
    "Permanent Add By Adjacent Count: permanent_add_by_adjacent_count",
    "Register Guard Aura: register_guard_aura",
    "Register Destroy Guard: register_destroy_guard",
    "Register Ward Redirect: register_ward",
    "Destroy Self On Decrease: destroy_on_decrease",
    "Gain On Adjacent Decrease: gain_on_adjacent_decrease",
    "Prevent Decrease (Filter): prevent_decrease",
    "Double Value Change: double_value_change",
    "Mirror Change To Random: mirror_change_random",
    "Adjust Run Total By Self Fraction: adjust_run_total_by_self_fraction",
    "Destroy Inventory Tag: destroy_inventory_tag",
    "Promote Killer To Path: promote_killer_to_path",
    "Lock Value (Filter+Revert): lock_value"
) var op: String = "add"
 
# Additional ops not producing direct commands but used by EffectSpec filter/handlers:
@export var enable_prevent_decrease: bool = false  # unused placeholder for editor hint

# Common numeric parameters
## For add/permanent_add/adjust_run_total: the amount to add/subtract.
@export var amount: int = 0

## Optional range for randomized amount (if both non-zero or max > min).
@export var min_amount: int = 0
@export var max_amount: int = 0

## For mult: the multiplier factor (e.g., 2.0 doubles value).
@export var factor: float = 1.0

# Description override for UI/log
## Optional UI text. Supports %d (amount), %f (factor), %s (source name).
@export var desc_template: String = ""

# Optional local conditions for this action
## Extra conditions for this action (in addition to EffectSpec conditions).
@export var conditions: Array[AbilityCondition] = []

# Optional shared roll group. If set (non-empty) and this action uses min/max amount,
# EffectSpec will roll once per (group+effect+token) per spin and reuse for all actions with the same key.
@export var shared_roll_key: String = ""

# Optional per-action targeting override. If empty, EffectSpec/TokenAbility targeting is used.
# Examples: "self", "neighbors", "offset", "tag", "name", "left", "right", "edges", "any", "active", "passive", "choose".
## Optional per-action target override. If blank, EffectSpec/TokenAbility target is used.
@export_enum(
    "(Use Effect Targeting):",
    "Self: self",
    "Winner (Center): middle",
    "Slot Offset: offset",
    "Neighbors: neighbors",
    "Left Neighbor: left",
    "Right Neighbor: right",
    "Edge Slots: edges",
    "Any Triggered: any",
    "Only Winner Slot: active",
    "Only Passive Slots: passive",
    "By Tag: tag",
    "By Name: name",
    "Player Chooses: choose"
) var target_override_kind: String = ""

## For target_override_kind == "offset": relative slot (-2..2).
@export var target_offset: int = 0

## For target_override_kind == "tag": tag to match.
@export var target_tag: String = ""

## For target_override_kind == "name": exact token name to match.
@export var target_name: String = ""

# Selection policy for multi-target actions/steps
@export_enum("All", "One Random", "N Random", "Player Chooses") var choose_mode: String = "All"
@export var choose_count: int = 1

# Specialized parameters for certain ops
## For set_perm_to_value: desired value to set
@export var target_value: int = 0

## For destroy_and_gain_fraction: numerator/denominator of gain
@export var gain_numer: int = 1
@export var gain_denom: int = 2

## For spawn_random_by_rarity: rarity label (common|uncommon|rare|legendary)
@export var rarity: String = ""

## For destroy_lowest_triggered: whether to exclude the source token
@export var exclude_self: bool = true

## For destroy_random_triggered_by_rarity_and_gain: match any rarity and whether gain goes to self
@export var match_any_rarity: bool = false
@export var gain_to_self: bool = true

## For replace_from_choices: a list of token paths to choose randomly from
@export var token_paths: PackedStringArray = PackedStringArray()

# Replace specifics
## For op == "replace": path to the replacement token resource (e.g., res://tokens/coin.tres).
@export var token_path: String = ""

## For replace: if true, copy tags from removed token to new one.
@export var preserve_tags: bool = false

## For replace: if true, seed replacement token's value from `amount`.
@export var set_value_from_amount: bool = false

## For copy_target_to_inventory: copies the chosen/target token into inventory
# (no extra fields needed; executor resolves from target_offset/choose)

# On-acquire replacement parameters
## For replace_self_with_random_inventory on acquire: selection behavior
# Use the same 'exclude_self' flag declared above for destroy_lowest_triggered
@export var require_different_name: bool = true

# Inventory-derived count helpers
@export var count_tag: String = ""
@export var count_name: String = ""

# Inventory destroy parameters (on-removed or commands):
@export var inventory_tag: String = ""
@export var max_destroy: int = 0
@export var inventory_name: String = ""
@export var max_replace: int = 0
@export var preserve_tags_for_replace: bool = false

# Name parameter for bulk destroy ops
@export var token_name: String = ""

# Permanent add specifics
## For permanent_add: if true, destroy tokens that drop below 1 permanently.
@export var destroy_if_zero: bool = false

## For permanent_add targeting self/offset: also apply to all tokens with the same internal key ("same copies").
@export var propagate_same_key: bool = false

# Register guard parameters
## For register_destroy_guard: threshold to block destroy of triggered tokens with lower value; if <= 0, EffectSpec computes from self.
@export var min_value_threshold: int = 0
## For register_destroy_guard: if true, only protect triggered row; otherwise global.
@export var triggered_only: bool = true
