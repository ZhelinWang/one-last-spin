extends Resource
class_name TokenAbility

## Base ability for tokens/artifacts.
## Designers can attach Ability resources to a token's `abilities` list.
## Each ability can emit spin steps (temporary adds/mults), global steps on the winner,
## and/or inventory/board commands.

## When the ability runs.
## - ACTIVE_DURING_SPIN: runs as part of the spin (most abilities)
## - ON_ACQUIRE: runs when the token is acquired/added to inventory
## - ON_REMOVED: runs when the token is removed/destroyed
enum Trigger { ACTIVE_DURING_SPIN, ON_ACQUIRE, ON_REMOVED }

## How this ability picks targets for its effects.
## - SELF: the source token only (usually the winner during final phase)
## - MIDDLE: the center slot (winner) regardless of source
## - OFFSET: specific offset relative to center (-2,-1,0,1,2)
## - TAG: any token with a matching tag (case-insensitive)
## - NAME: any token with an exact name match
## - ANY: all tokens (broadcast)
## - NEIGHBORS: adjacent left and right slots (offset -1 and +1)
## - LEFT/RIGHT: neighbor immediately left/right of center
## - EDGES: outer slots (offset -2 and +2)
## - ACTIVE/PASSIVE: only the active (center) or passive (others) contribs
## - OTHERS: everyone except the source token
enum TargetKind { SELF, MIDDLE, OFFSET, TAG, NAME, ANY, NEIGHBORS, LEFT, RIGHT, EDGES, ACTIVE, PASSIVE, OTHERS }

## Legacy helper: if true and no custom builders are provided, autogenerates a simple self step
## from `amount`/`factor` fields on the ability (if present). Prefer explicit builders.
@export var auto_self_step: bool = false

## Unique identifier for debugging, analytics, and description logs.
@export var id: String = ""

## When the ability runs. See Trigger enum above.
@export var trigger: Trigger = Trigger.ACTIVE_DURING_SPIN

## How to pick targets for non-self/global steps and commands. See TargetKind.
@export var target_kind: TargetKind = TargetKind.SELF

## For target_kind == OFFSET: which slot relative to center (-2..2)
@export var target_offset: int = 0

## For target_kind == TAG: tag to match (case-insensitive)
@export var target_tag: String = ""

## For target_kind == NAME: exact token name to match
@export var target_name: String = ""

## If true, effects only apply when this token is the winner (center slot) this spin.
@export var winner_only: bool = false

## Optional text template for UI logs. Supports %d (amount), %f (factor), %s (source name).
@export var desc_template: String = ""

func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
	return []

func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	print([])
	return []

func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
	return []

# Optional: commands when a token is removed (executor hook)
func build_on_removed_commands(ctx: Dictionary, removed_token: Resource, source_token: Resource) -> Array:
	return []

func filter_step(ctx: Dictionary, step: Dictionary, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}) -> Variant:
	return step

func on_value_changed(ctx: Dictionary, prev_val: int, new_val: int, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}, step: Dictionary = {}) -> void:
	pass

func wants_auto_self_step() -> bool: return auto_self_step
# Lifecycle (executor may call these based on game events)
func on_acquire(board_tokens: Array, ctx: Dictionary, source_token: Resource) -> void: pass
func on_added_to_inventory(board_tokens: Array, ctx: Dictionary, source_token: Resource) -> void: pass
func on_removed(board_tokens: Array, ctx: Dictionary, source_token: Resource, reason: String = "") -> void: pass
func on_not_triggered(ctx: Dictionary, source_token: Resource) -> void: pass

# Called by the executor when ANY token on the board is destroyed/replaced with Empty.
# Return an array of commands to execute (same structure as build_commands), or [] to ignore.
func on_any_token_destroyed(ctx: Dictionary, destroyed_token: Resource, source_token: Resource) -> Array:
	return []

# ---------- helpers ----------
func is_active_during_spin() -> bool:
	return trigger == Trigger.ACTIVE_DURING_SPIN

func matches_target(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> bool:
	if winner_only and int(contrib.get("offset", 99)) != 0:
		return false
	var off: int = int(contrib.get("offset", 99))
	var token = contrib.get("token")
	var result := false
	if target_kind == TargetKind.SELF:
		result = token == source_token
	elif target_kind == TargetKind.MIDDLE:
		result = off == 0
	elif target_kind == TargetKind.OFFSET:
		result = off == target_offset
	elif target_kind == TargetKind.TAG:
		result = _token_has_tag(token, target_tag)
	elif target_kind == TargetKind.NAME:
		result = _token_name(token) == target_name
	elif target_kind == TargetKind.NEIGHBORS:
		result = abs(off) == 1
	elif target_kind == TargetKind.LEFT:
		result = off == -1
	elif target_kind == TargetKind.RIGHT:
		result = off == 1
	elif target_kind == TargetKind.EDGES:
		result = abs(off) == 2
	elif target_kind == TargetKind.ACTIVE:
		result = String(contrib.get("kind", "")).to_lower() == "active"
	elif target_kind == TargetKind.PASSIVE:
		result = String(contrib.get("kind", "")).to_lower() == "passive"
	elif target_kind == TargetKind.OTHERS:
		result = token != source_token
	elif target_kind == TargetKind.ANY:
		result = true
	return result

func _tk_to_string() -> String:
	match target_kind:
		TargetKind.SELF: return "self"
		TargetKind.MIDDLE: return "middle"
		TargetKind.OFFSET: return "offset"
		TargetKind.TAG: return "tag"
		TargetKind.NAME: return "name"
		TargetKind.NEIGHBORS: return "neighbors"
		TargetKind.LEFT: return "left"
		TargetKind.RIGHT: return "right"
		TargetKind.EDGES: return "edges"
		TargetKind.ACTIVE: return "active"
		TargetKind.PASSIVE: return "passive"
		TargetKind.OTHERS: return "others"
		TargetKind.ANY: return "any"
	return "any"

func _mk_add(amount: int, desc: String, src: String) -> Dictionary:
	return {"kind":"add","amount":amount,"factor":1.0,"desc":desc,"source":src}

func _mk_mult(factor: float, desc: String, src: String) -> Dictionary:
	return {"kind":"mult","amount":0,"factor":max(factor,0.0),"desc":desc,"source":src}

# Compatibility aliases for abilities that call *_step or make_global_step
func _mk_add_step(amount: int, desc: String, src: String) -> Dictionary:
	return _mk_add(amount, desc, src)

func _mk_mult_step(factor: float, desc: String, src: String) -> Dictionary:
	return _mk_mult(factor, desc, src)

func mk_global_step(kind: String, amount: int, factor: float, desc: String, src: String) -> Dictionary:
	return {
		"kind": kind, "amount": amount, "factor": factor, "desc": desc, "source": src,
		"target_kind": _tk_to_string(), "target_offset": target_offset,
		"target_tag": target_tag, "target_name": target_name
	}

func make_global_step(kind: String, amount: int, factor: float, desc: String, src: String) -> Dictionary:
	return mk_global_step(kind, amount, factor, desc, src)

func _token_name(t) -> String:
	if t != null and t.has_method("get"):
		var n = t.get("name")
		if typeof(n) == TYPE_STRING:
			return String(n)
	return ""

func _token_has_tag(t, tag: String) -> bool:
	if t == null or not t.has_method("get"):
		return false
	var tag_norm := tag.strip_edges().to_lower()
	if tag_norm == "":
		return false
	var tags = t.get("tags")
	if tags is Array:
		for s in tags:
			if typeof(s) == TYPE_STRING and String(s).to_lower() == tag_norm:
				return true
	elif typeof(tags) == TYPE_PACKED_STRING_ARRAY:
		var psa: PackedStringArray = tags
		for s in psa:
			if String(s).to_lower() == tag_norm:
				return true
	return false

func _is_coin(t) -> bool:
	return _token_has_tag(t, "coin") or _token_name(t).to_lower() == "coin"

func _is_worker(t) -> bool:
	return _token_has_tag(t, "worker") or _token_name(t).to_lower() == "worker"

func _contrib_value(c: Dictionary) -> int:
	var base: int = int(c.get("base", 0))
	var delta: int = int(c.get("delta", 0))
	var mult: float = float(c.get("mult", 1.0))
	var sum: int = base + delta
	if sum < 0: sum = 0
	return max(int(floor(sum * max(mult, 0.0))), 0)

func _find_self_contrib(contribs: Array, source_token: Resource) -> Dictionary:
	for c in contribs:
		if c is Dictionary and c.get("token") == source_token:
			return c
	return {}

func _neighbor_at_offset(contribs: Array, base_c: Dictionary, delta: int) -> Dictionary:
	if base_c.is_empty(): return {}
	var target_off: int = int(base_c.get("offset", 99)) + delta
	for c in contribs:
		if int(c.get("offset", 999)) == target_off:
			return c
	return {}

func _adjacent_contribs(contribs: Array, base_c: Dictionary) -> Array:
	var out: Array = []
	var l := _neighbor_at_offset(contribs, base_c, -1)
	var r := _neighbor_at_offset(contribs, base_c, 1)
	if not l.is_empty(): out.append(l)
	if not r.is_empty(): out.append(r)
	return out

func _count_in_inventory(ctx: Dictionary, tag: String) -> int:
	if ctx.has("board_tokens") and (ctx["board_tokens"] is Array):
		var cnt: int = 0
		for t in ctx["board_tokens"]:
			if _token_has_tag(t, tag):
				cnt += 1
		return cnt
	return 0
