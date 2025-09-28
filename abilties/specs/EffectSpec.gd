extends TokenAbility
class_name EffectSpec

# Data-driven ability composed of conditions and actions.
# - Inherits TokenAbility targeting fields (trigger, target_kind, winner_only, desc_template, etc.).
# - Evaluates effect-level conditions; if they pass, executes actions.
# - For step ops (add/mult):
#    - If target resolves to self, emit build_steps.
#    - If target resolves to non-self, emit build_final_steps (winner_only path is required by executor).
# - For commands (replace/permanent_add/destroy/adjust_run_total): emit build_commands.

## Determines relative ordering versus other effects (lower runs earlier). Usually leave at 100.
@export var priority: int = 100

## Conditions that must pass for this effect to run.
@export var conditions: Array[AbilityCondition] = []

## The list of actions this effect performs when conditions pass.
@export var actions: Array[AbilityAction] = []

## If true, this effect runs at most once per spin per token.
@export var once_per_spin: bool = false

func _str_eqi(a: String, b: String) -> bool:
    return a.strip_edges().to_lower() == b.strip_edges().to_lower()

func _once_key(source_token: Resource) -> String:
    var tok_part := ""
    if source_token != null:
        tok_part = ":" + str(source_token.get_instance_id())
    return "__once_effect:" + String(id) + tok_part

func _should_consider(ctx: Dictionary, source_token: Resource) -> bool:
    if not once_per_spin:
        return true
    return not bool(ctx.get(_once_key(source_token), false))

func _mark_emitted(ctx: Dictionary, source_token: Resource) -> void:
    if once_per_spin:
        ctx[_once_key(source_token)] = true

func _use_self_for_kind(kind_s: String) -> bool:
    var k := kind_s.strip_edges().to_lower()
    return k == "self" or k == "winner" or k == "middle"

func _resolve_action_target(action: AbilityAction) -> Dictionary:
    var tk: String = String(action.target_override_kind)
    tk = tk.strip_edges()
    if tk == "":
        # Default to ability targeting
        tk = _tk_to_string()
    return {
        "target_kind": tk.to_lower(),
        "target_offset": action.target_offset if action.target_override_kind != "" else int(target_offset),
        "target_tag": action.target_tag if action.target_override_kind != "" else String(target_tag),
        "target_name": action.target_name if action.target_override_kind != "" else String(target_name)
    }

func _desc_for_add(effect_src: String, action: AbilityAction, amt: int, src_name: String) -> String:
    var tpl := String(action.desc_template if action.desc_template.strip_edges() != "" else desc_template)
    if tpl.strip_edges() == "":
        return "+%d from %s" % [amt, src_name]
    if tpl.find("%d") != -1 and tpl.find("%s") != -1:
        return tpl % [amt, src_name]
    if tpl.find("%d") != -1:
        return tpl % [amt]
    if tpl.find("%s") != -1:
        return tpl % [src_name]
    return tpl

func _desc_for_mult(effect_src: String, action: AbilityAction, fac: float, src_name: String) -> String:
    var tpl := String(action.desc_template if action.desc_template.strip_edges() != "" else desc_template)
    if tpl.strip_edges() == "":
        return "x%.2f from %s" % [fac, src_name]
    if tpl.find("%f") != -1 and tpl.find("%s") != -1:
        return tpl % [fac, src_name]
    if tpl.find("%f") != -1:
        return tpl % [fac]
    if tpl.find("%s") != -1:
        return tpl % [src_name]
    return tpl

func _conditions_pass(ctx: Dictionary, contrib: Dictionary, contribs: Array, source_token: Resource, extra: Array[AbilityCondition]) -> bool:
    # Evaluate effect-level and then action-level conditions
    for cond in conditions:
        if cond == null: continue
        if not cond.passes(ctx, contrib, contribs, source_token, self):
            return false
    if extra != null:
        for c2 in extra:
            if c2 == null: continue
            if not c2.passes(ctx, contrib, contribs, source_token, self):
                return false
    return true

# ---------- build steps (per-token/self) ----------
func build_steps(ctx: Dictionary, contrib: Dictionary, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    if actions.is_empty():
        return []
    if not _should_consider(ctx, source_token):
        return []
    # Gate by standard target match (self-based filtering only)
    if not matches_target(ctx, contrib, source_token):
        return []
    var out: Array = []
    var src_name := _token_name(source_token)
    var src := "ability:%s" % String(id)
    for act in actions:
        if act == null: continue
        var op := String(act.op).strip_edges().to_lower()
        if op != "add" and op != "mult":
            continue
        var tgt := _resolve_action_target(act)
        if not _use_self_for_kind(String(tgt.get("target_kind", "self"))):
            # Non-self spin steps will be emitted in build_final_steps
            continue
        if not _conditions_pass(ctx, contrib, [], source_token, act.conditions):
            continue
        if op == "add":
            var amt: int = int(act.amount)
            if amt != 0:
                var desc := _desc_for_add(src, act, amt, src_name)
                out.append(_mk_add_step(amt, desc, src))
        elif op == "mult":
            var fac: float = max(0.0, float(act.factor))
            if abs(fac - 1.0) > 0.0001:
                var desc2 := _desc_for_mult(src, act, fac, src_name)
                out.append(_mk_mult_step(fac, desc2, src))
    if not out.is_empty():
        _mark_emitted(ctx, source_token)
    return out

# ---------- build final steps (winner/global targeting) ----------
func build_final_steps(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    if actions.is_empty():
        return []
    if not _should_consider(ctx, source_token):
        return []
    var out: Array = []
    var src_name := _token_name(source_token)
    var src := "ability:%s" % String(id)
    for act in actions:
        if act == null: continue
        var op := String(act.op).strip_edges().to_lower()
        if op != "add" and op != "mult":
            continue
        var tgt := _resolve_action_target(act)
        var tk := String(tgt.get("target_kind", "any"))
        # Allow self-targeted emission here only when winner_only = true to avoid duplicates with per-token phase
        if _use_self_for_kind(tk) and not winner_only:
            continue
        if not _conditions_pass(ctx, {}, contribs, source_token, act.conditions):
            continue
        if op == "add":
            var amt: int = int(act.amount)
            if amt != 0:
                var desc := _desc_for_add(src, act, amt, src_name)
                var step := mk_global_step("add", amt, 1.0, desc, src)
                step["target_kind"] = tk
                step["target_offset"] = int(tgt.get("target_offset", target_offset))
                step["target_tag"] = String(tgt.get("target_tag", target_tag))
                step["target_name"] = String(tgt.get("target_name", target_name))
                out.append(step)
        elif op == "mult":
            var fac: float = max(0.0, float(act.factor))
            if abs(fac - 1.0) > 0.0001:
                var desc2 := _desc_for_mult(src, act, fac, src_name)
                var step2 := mk_global_step("mult", 0, fac, desc2, src)
                step2["target_kind"] = tk
                step2["target_offset"] = int(tgt.get("target_offset", target_offset))
                step2["target_tag"] = String(tgt.get("target_tag", target_tag))
                step2["target_name"] = String(tgt.get("target_name", target_name))
                out.append(step2)
    if not out.is_empty():
        _mark_emitted(ctx, source_token)
    return out

# ---------- build commands (inventory/board mutations) ----------
func build_commands(ctx: Dictionary, contribs: Array, source_token: Resource) -> Array:
    if trigger != TokenAbility.Trigger.ACTIVE_DURING_SPIN:
        return []
    if actions.is_empty():
        return []
    if not _should_consider(ctx, source_token):
        return []
    var out: Array = []
    var src := "ability:%s" % String(id)
    for act in actions:
        if act == null: continue
        var op := String(act.op).strip_edges().to_lower()
        if op == "add" or op == "mult":
            continue
        var tgt := _resolve_action_target(act)
        if not _conditions_pass(ctx, {}, contribs, source_token, act.conditions):
            continue
        match op:
            "permanent_add":
                var cmd_pa := {
                    "op": "permanent_add",
                    "target_kind": String(tgt.get("target_kind", _tk_to_string())),
                    "target_offset": int(tgt.get("target_offset", target_offset)),
                    "target_tag": String(tgt.get("target_tag", target_tag)),
                    "target_name": String(tgt.get("target_name", target_name)),
                    "amount": int(act.amount),
                    "destroy_if_zero": bool(act.destroy_if_zero),
                    "propagate_same_key": bool(act.propagate_same_key),
                    "source": src
                }
                out.append(cmd_pa)
            "replace":
                var tk := String(tgt.get("target_kind", _tk_to_string())).to_lower()
                var path := String(act.token_path)
                if path.strip_edges() == "":
                    continue
                if tk == "offset":
                    var s_val := -1
                    if act.set_value_from_amount:
                        s_val = int(max(1, int(act.amount)))
                    out.append({
                        "op": "replace_at_offset",
                        "offset": int(tgt.get("target_offset", 0)),
                        "token_path": path,
                        "set_value": s_val,
                        "preserve_tags": bool(act.preserve_tags),
                        "source": src
                    })
                elif tk == "tag":
                    out.append({
                        "op": "replace_board_tag",
                        "target_tag": String(tgt.get("target_tag", "")),
                        "token_path": path,
                        "source": src
                    })
                elif tk == "any":
                    # Inventory empties and current board empties
                    out.append({
                        "op": "replace_all_empties",
                        "token_path": path,
                        "source": src
                    })
                    out.append({
                        "op": "replace_board_empties",
                        "token_path": path,
                        "source": src
                    })
            "destroy":
                # supported as offset-destroy in current executor
                var tkd := String(tgt.get("target_kind", _tk_to_string())).to_lower()
                var d := {
                    "op": "destroy",
                    "target_offset": int(tgt.get("target_offset", 0)),
                    "source": src
                }
                # Mark chooser intent so executor can prompt for a target
                if tkd == "choose":
                    d["target_kind"] = "choose"
                    d["choose"] = true
                out.append(d)
            "adjust_run_total":
                var amt := int(act.amount)
                if amt != 0:
                    out.append({"op": "adjust_run_total", "amount": amt, "source": src})
            _:
                # Unknown ops are ignored; keep system resilient
                pass
    if not out.is_empty():
        _mark_emitted(ctx, source_token)
    return out
