# GenericDuplicateOnAddAbility
# Effect:
# - When the source token is added to the inventory, ensure there are exactly `total_copies` of this token
#   (including the original) present by spawning additional copies as needed.
# - This is a one-time reaction to the “added to inventory” lifecycle event; it should be idempotent and
#   must not create more than `total_copies` total.
#
# Usage:
# - Attach to a token resource and set `total_copies` (>= 1). For example, 2 means “make one extra copy”.
# - Your executor (CoinManager or a helper) must call `on_added_to_inventory` when the token is added.
# - Implement duplication in the executor by:
#   - Counting existing copies of the same token/resource (by identity or a shared ID), then
#   - Instantiating duplicates with `duplicate(true)` until the total equals `total_copies`,
#   - Placing them according to your inventory rules (e.g., fill first/last/random Empty).
#
# Notes:
# - If the inventory lacks space, the executor should either queue the request or stop at capacity.
# - To centralize behavior, you can emit a command instead of direct duplication, e.g.:
#   { op: "ensure_total_copies_for_self", count: total_copies }
#   and handle it in your executor.
# - Be careful with simultaneous adds: de-duplicate in the executor to avoid overshooting the target count.

extends TokenAbility
class_name GenericDuplicateOnAddAbility

@export var total_copies: int = 2

func on_added_to_inventory(board_tokens: Array, ctx: Dictionary, source_token: Resource) -> void:
	# Executor should ensure total equals total_copies by spawning (total_copies-1) extra copies.
	# Alternatively, emit a command if your executor supports it:
	# ctx["commands"].append({"op":"ensure_total_copies_for_self","count":total_copies})
	pass
