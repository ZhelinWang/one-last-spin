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

# Pre-step filter: allow preventing decreases via spec action
func filter_step(ctx: Dictionary, step: Dictionary, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}) -> Variant:
    if actions.is_empty():
        return step
    if winner_only and int(target_contrib.get("offset", 99)) != 0:
        return step
    for act in actions:
        if act == null:
            continue
        var op := String(act.op).strip_edges().to_lower()
        if op == "prevent_decrease" and target_token == source_token:
            var kind := String(step.get("kind", ""))
            if kind == "add" and int(step.get("amount", 0)) < 0:
                return null
            if kind == "mult" and float(step.get("factor", 1.0)) < 1.0:
                return null
    return step

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

func _mk_rng(ctx: Dictionary) -> RandomNumberGenerator:
    var rng: RandomNumberGenerator = ctx.get("rng") if ctx != null and ctx.has("rng") else RandomNumberGenerator.new()
    if ctx == null or not ctx.has("rng"):
        rng.randomize()
    return rng

func _roll_amount(act: AbilityAction, ctx: Dictionary) -> int:
    var lo := int(act.min_amount)
    var hi := int(act.max_amount)
    if hi < lo:
        var tmp := lo
        lo = hi
        hi = tmp
    if hi > lo:
        var rng := _mk_rng(ctx)
        return int(rng.randi_range(lo, hi))
    if lo != 0 and hi == lo:
        return lo
    return int(act.amount)

func _count_in_inventory_by_name(ctx: Dictionary, name: String) -> int:
    if ctx == null or not (ctx is Dictionary):
        return 0
    var arr = ctx.get("board_tokens")
    if not (arr is Array):
        return 0
    var n := 0
    for t in arr:
        if t != null and (t as Object).has_method("get"):
            var nm = t.get("name")
            if nm != null and String(nm).strip_edges().to_lower() == name.strip_edges().to_lower():
                n += 1
    return n

func _collect_candidate_offsets(contribs: Array, source_token: Resource, tgt: Dictionary) -> Array[int]:
    var tk := String(tgt.get("target_kind", _tk_to_string())).to_lower()
    var res: Array[int] = []
    match tk:
        "any", "all":
            for c in contribs:
                if c is Dictionary:
                    res.append(int((c as Dictionary).get("offset", 0)))
        "self", "winner", "middle":
            res.append(0)
        "others", "not_self":
            for c in contribs:
                if c is Dictionary and (c as Dictionary).get("token") != source_token:
                    res.append(int((c as Dictionary).get("offset", 0)))
        "neighbors", "adjacent":
            res.append(-1)
            res.append(1)
        "left":
            res.append(-1)
        "right":
            res.append(1)
        "edges", "outer":
            res.append(-2)
            res.append(2)
        "active":
            for c in contribs:
                if String((c as Dictionary).get("kind", "")).to_lower() == "active":
                    res.append(int((c as Dictionary).get("offset", 0)))
        "passive":
            for c in contribs:
                if String((c as Dictionary).get("kind", "")).to_lower() == "passive":
                    res.append(int((c as Dictionary).get("offset", 0)))
        "offset":
            res.append(int(tgt.get("target_offset", target_offset)))
        "tag":
            var tag := String(tgt.get("target_tag", target_tag))
            for c in contribs:
                if _token_has_tag((c as Dictionary).get("token"), tag):
                    res.append(int((c as Dictionary).get("offset", 0)))
        "name":
            var nm := String(tgt.get("target_name", target_name))
            for c in contribs:
                if _token_name((c as Dictionary).get("token")) == nm:
                    res.append(int((c as Dictionary).get("offset", 0)))
        _:
            for c in contribs:
                res.append(int((c as Dictionary).get("offset", 0)))
    var filtered_basic: Array[int] = []
    for off in res:
        if abs(int(off)) <= 2:
            filtered_basic.append(int(off))
    # Optional post-filter by tag/name if provided on target descriptor
    var want_tag := String(tgt.get("target_tag", "")).strip_edges().to_lower()
    var want_name := String(tgt.get("target_name", "")).strip_edges()
    if want_tag == "" and want_name == "":
        return filtered_basic
    var filtered: Array[int] = []
    for off2 in filtered_basic:
        var found: bool = false
        for c in contribs:
            if not (c is Dictionary):
                continue
            if int((c as Dictionary).get("offset", 999)) != int(off2):
                continue
            var tok = (c as Dictionary).get("token")
            var ok := true
            if want_tag != "":
                ok = _token_has_tag(tok, want_tag)
            if ok and want_name.strip_edges() != "":
                ok = _str_eqi(_token_name(tok), want_name)
            if ok:
                found = true
            break
        if found:
            filtered.append(int(off2))
    return filtered

func _choose_offsets(candidates: Array[int], act: AbilityAction, ctx: Dictionary) -> Array[int]:
    var mode := String(act.choose_mode)
    var cnt := max(1, int(act.choose_count))
    if candidates.is_empty():
        return []
    if mode == "All":
        return candidates.duplicate()
    if mode == "One Random":
        var rng := _mk_rng(ctx)
        return [candidates[rng.randi_range(0, candidates.size() - 1)]]
    if mode == "N Random":
        var rng2 := _mk_rng(ctx)
        var pool := candidates.duplicate()
        var out: Array[int] = []
        var want := min(cnt, pool.size())
        for i in range(want):
            var idx := rng2.randi_range(0, pool.size() - 1)
            out.append(int(pool[idx]))
            pool.remove_at(idx)
        return out
    return candidates.duplicate()

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
            var amt: int = _roll_amount(act, ctx)
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
            var amt: int = _roll_amount(act, ctx)
            if amt != 0:
                var desc := _desc_for_add(src, act, amt, src_name)
                var cands := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks := _choose_offsets(cands, act, ctx)
                for off in picks:
                    var step := mk_global_step("add", amt, 1.0, desc, src)
                    step["target_kind"] = "offset"
                    step["target_offset"] = int(off)
                    out.append(step)
        elif op == "mult":
            var fac: float = max(0.0, float(act.factor))
            if abs(fac - 1.0) > 0.0001:
                var desc2 := _desc_for_mult(src, act, fac, src_name)
                var cands2 := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks2 := _choose_offsets(cands2, act, ctx)
                for off2 in picks2:
                    var step2 := mk_global_step("mult", 0, fac, desc2, src)
                    step2["target_kind"] = "offset"
                    step2["target_offset"] = int(off2)
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
                var tkp := String(tgt.get("target_kind", _tk_to_string())).to_lower()
                var amt_pa := int(_roll_amount(act, ctx))
                if amt_pa == 0:
                    pass
                elif tkp == "choose":
                    var d_pa := {
                        "op": "permanent_add",
                        "target_kind": "choose",
                        "choose": true,
                        "amount": amt_pa,
                        "destroy_if_zero": bool(act.destroy_if_zero),
                        "propagate_same_key": bool(act.propagate_same_key),
                        "source": src
                    }
                    out.append(d_pa)
                elif (tkp == "offset" or tkp == "self" or tkp == "tag" or tkp == "name") and String(act.choose_mode) == "All":
                    var cmd_pa := {
                        "op": "permanent_add",
                        "target_kind": tkp,
                        "target_offset": int(tgt.get("target_offset", target_offset)),
                        "target_tag": String(tgt.get("target_tag", target_tag)),
                        "target_name": String(tgt.get("target_name", target_name)),
                        "amount": amt_pa,
                        "destroy_if_zero": bool(act.destroy_if_zero),
                        "propagate_same_key": bool(act.propagate_same_key),
                        "source": src
                    }
                    out.append(cmd_pa)
                else:
                    # Resolve group targets (neighbors/edges/active/passive/etc.) into explicit offsets
                    var cands_pa := _collect_candidate_offsets(contribs, source_token, tgt)
                    var picks_pa := _choose_offsets(cands_pa, act, ctx)
                    for off_pa in picks_pa:
                        out.append({
                            "op": "permanent_add",
                            "target_kind": "offset",
                            "target_offset": int(off_pa),
                            "amount": amt_pa,
                            "destroy_if_zero": bool(act.destroy_if_zero),
                            "propagate_same_key": bool(act.propagate_same_key),
                            "source": src
                        })
            "replace":
                var tk := String(tgt.get("target_kind", _tk_to_string())).to_lower()
                var path := String(act.token_path)
                if path.strip_edges() == "":
                    continue
                if tk == "offset":
                    var s_val := -1
                    if act.set_value_from_amount:
                        s_val = int(max(1, int(_roll_amount(act, ctx))))
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
                if tkd == "tag":
                    # Triggered-row tag destroy convenience
                    out.append({
                        "op": "destroy_triggered_tag",
                        "target_tag": String(tgt.get("target_tag", "")),
                        "source": src
                    })
                elif tkd == "choose":
                    var count := max(1, int(act.choose_count))
                    for i in range(count):
                        out.append({"op": "destroy", "target_kind": "choose", "choose": true, "source": src})
                else:
                    var cands := _collect_candidate_offsets(contribs, source_token, tgt)
                    var picks := _choose_offsets(cands, act, ctx)
                    if picks.is_empty():
                        picks = [int(tgt.get("target_offset", 0))]
                    for off in picks:
                        out.append({"op": "destroy", "target_offset": int(off), "source": src})
            "double_target_permanent":
                var cands_d := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks_d := _choose_offsets(cands_d, act, ctx)
                if picks_d.is_empty(): picks_d = [int(tgt.get("target_offset", 0))]
                for offd in picks_d:
                    out.append({"op": "double_target_permanent", "target_offset": int(offd), "source": src})
            "set_perm_to_self_current":
                var cands_s := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks_s := _choose_offsets(cands_s, act, ctx)
                if picks_s.is_empty(): picks_s = [int(tgt.get("target_offset", 0))]
                for offs in picks_s:
                    out.append({"op": "set_perm_to_self_current", "target_offset": int(offs), "source": src})
            "set_self_perm_to_target_current":
                var cands_t := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks_t := _choose_offsets(cands_t, act, ctx)
                if picks_t.is_empty(): picks_t = [int(tgt.get("target_offset", 0))]
                for offt in picks_t:
                    out.append({"op": "set_self_perm_to_target_current", "target_offset": int(offt), "source": src})
            "destroy_and_gain_fraction":
                var cands_f := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks_f := _choose_offsets(cands_f, act, ctx)
                if picks_f.is_empty(): picks_f = [int(tgt.get("target_offset", 0))]
                var numer := max(0, int(act.gain_numer))
                var denom := max(1, int(act.gain_denom))
                for offf in picks_f:
                    out.append({"op": "destroy_and_gain_fraction", "target_offset": int(offf), "gain_numer": numer, "gain_denom": denom, "source": src})
            "replace_target_with_self_copy":
                var cands_rc := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks_rc := _choose_offsets(cands_rc, act, ctx)
                if picks_rc.is_empty(): picks_rc = [int(tgt.get("target_offset", 0))]
                for offr2 in picks_rc:
                    out.append({"op": "replace_at_offset", "offset": int(offr2), "token_ref": source_token, "source": src})
            "replace_self_random_by_tag":
                var tagrs := String(tgt.get("target_tag", target_tag))
                var troot := String(loot_scan_root)
                out.append({"op": "replace_self_random_by_tag", "target_tag": tagrs, "tokens_root": troot, "source": src})
            "replace_self_with_random_inventory":
                out.append({"op": "replace_self_with_random_inventory", "source": src})
            "mastermind_destroy_target_and_buff":
                # Player chooses target; executor handles destroying target and buffing others by its value
                out.append({"op": "mastermind_destroy_target_and_buff", "target_kind": "choose", "choose": true, "source": src})
            "permanent_add_by_adjacent_count":
                # Count adjacent matches (by tag/name via target descriptor), add that much to self
                var cands_adj := _collect_candidate_offsets(contribs, source_token, tgt)
                var adj_count := int(cands_adj.size())
                if adj_count > 0:
                    out.append({"op": "permanent_add", "target_kind": "self", "amount": adj_count, "destroy_if_zero": false, "source": src})
            "register_guard_aura":
                # Register self as a guard aura (indestructible)
                var self_c_rg := _find_self_contrib(contribs, source_token)
                if not self_c_rg.is_empty():
                    out.append({"op": "register_guard_aura", "offset": int(self_c_rg.get("offset", 0)), "source": src})
            "register_ward":
                # Register self as a ward (redirect adjacent destroys)
                var self_c_rw := _find_self_contrib(contribs, source_token)
                if not self_c_rw.is_empty():
                    out.append({"op": "register_ward", "offset": int(self_c_rw.get("offset", 0)), "source": src})
            "register_destroy_guard":
                # Guard that blocks destroy/replace for triggered tokens with value below threshold
                var self_c_rd := _find_self_contrib(contribs, source_token)
                if not self_c_rd.is_empty():
                    var thr := int(act.min_value_threshold)
                    if thr <= 0:
                        thr = _contrib_value(self_c_rd)
                    out.append({"op": "register_destroy_guard", "offset": int(self_c_rd.get("offset", 0)), "min_value_threshold": thr, "triggered_only": bool(act.triggered_only), "source": src})
            "copy_target_to_inventory":
                var cands_ct := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks_ct := _choose_offsets(cands_ct, act, ctx)
                if picks_ct.is_empty(): picks_ct = [int(tgt.get("target_offset", 0))]
                for offct in picks_ct:
                    out.append({"op": "copy_target_to_inventory", "target_offset": int(offct), "source": src})
            "set_perm_to_value":
                # Compute delta to reach target_value on resolved targets
                var desired := int(act.target_value)
                if desired != 0:
                    var tk_sv := String(tgt.get("target_kind", _tk_to_string())).to_lower()
                    var offs_sv := []
                    if tk_sv == "self" or tk_sv == "winner" or tk_sv == "middle":
                        offs_sv = [0]
                    else:
                        offs_sv = _choose_offsets(_collect_candidate_offsets(contribs, source_token, tgt), act, ctx)
                        if offs_sv.is_empty(): offs_sv = [int(tgt.get("target_offset", 0))]
                    for offsv in offs_sv:
                        var target_c_local: Dictionary = {}
                        for ctmp in contribs:
                            if ctmp is Dictionary and int((ctmp as Dictionary).get("offset", 999)) == int(offsv):
                                target_c_local = ctmp
                                break
                        if not target_c_local.is_empty():
                            var cur := _contrib_value(target_c_local)
                            var delta := desired - cur
                            if delta != 0:
                                out.append({"op": "permanent_add", "target_kind": "offset", "target_offset": int(offsv), "amount": delta, "destroy_if_zero": false, "source": src})
            "permanent_add_by_inventory_count":
                var cnt: int = 0
                if String(act.count_name).strip_edges() != "":
                    cnt = _count_in_inventory_by_name(ctx, String(act.count_name))
                elif String(act.count_tag).strip_edges() != "":
                    cnt = _count_in_inventory(ctx, String(act.count_tag))
                var total := int(act.amount) * int(cnt)
                if total != 0:
                    var tkp2 := String(tgt.get("target_kind", _tk_to_string())).to_lower()
                    if tkp2 == "offset" or tkp2 == "self" or tkp2 == "tag" or tkp2 == "name":
                        out.append({"op": "permanent_add", "target_kind": tkp2, "target_offset": int(tgt.get("target_offset", target_offset)), "target_tag": String(tgt.get("target_tag", target_tag)), "target_name": String(tgt.get("target_name", target_name)), "amount": total, "destroy_if_zero": false, "source": src})
                    else:
                        var cands_pa3 := _collect_candidate_offsets(contribs, source_token, tgt)
                        var picks_pa3 := _choose_offsets(cands_pa3, act, ctx)
                        for offp3 in picks_pa3:
                            out.append({"op": "permanent_add", "target_kind": "offset", "target_offset": int(offp3), "amount": total, "destroy_if_zero": false, "source": src})
            "destroy_all_copies_by_name":
                var nm_act := String(act.token_name)
                if nm_act.strip_edges() != "":
                    out.append({"op": "destroy_all_copies_by_name", "token_name": nm_act, "source": src})
            "add_from_self_current":
                var self_c3 := _find_self_contrib(contribs, source_token)
                if self_c3.is_empty():
                    continue
                var self_val3 := _contrib_value(self_c3)
                if self_val3 != 0:
                    var cands_a := _collect_candidate_offsets(contribs, source_token, tgt)
                    var picks_a := _choose_offsets(cands_a, act, ctx)
                    for offa in picks_a:
                        var step_add := mk_global_step("add", int(self_val3), 1.0, desc_template, src)
                        step_add["target_kind"] = "offset"
                        step_add["target_offset"] = int(offa)
                        out.append(step_add)
            "trigger_loot_selection":
                out.append({"op": "trigger_loot_selection", "source": src})
            "destroy_non_triggered_empties":
                out.append({"op": "destroy_non_triggered_empties", "source": src})
            "reroll_same_rarity":
                var cands_r := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks_r := _choose_offsets(cands_r, act, ctx)
                if picks_r.is_empty(): picks_r = [int(tgt.get("target_offset", 0))]
                for offr in picks_r:
                    out.append({"op": "reroll_same_rarity", "target_offset": int(offr), "source": src})
            "replace_by_rarity":
                var mode := "demote"
                var tplm := String(desc_template)
                if tplm.to_lower().find("promote") != -1:
                    mode = "promote"
                var cands_b := _collect_candidate_offsets(contribs, source_token, tgt)
                var picks_b := _choose_offsets(cands_b, act, ctx)
                if picks_b.is_empty(): picks_b = [int(tgt.get("target_offset", 0))]
                for offb in picks_b:
                    out.append({"op": "replace_by_rarity", "target_offset": int(offb), "mode": mode, "source": src})
            "replace_from_choices":
                var tkc := String(tgt.get("target_kind", _tk_to_string())).to_lower()
                var choices: PackedStringArray = act.token_paths
                if choices.size() == 0:
                    continue
                if tkc == "choose":
                    var cntc := max(1, int(act.choose_count))
                    for i in range(cntc):
                        out.append({"op": "replace_at_offset_from_choices", "target_kind": "choose", "choose": true, "token_paths": choices, "source": src})
                else:
                    var cands_c := _collect_candidate_offsets(contribs, source_token, tgt)
                    var picks_c := _choose_offsets(cands_c, act, ctx)
                    if picks_c.is_empty(): picks_c = [int(tgt.get("target_offset", 0))]
                    for offc in picks_c:
                        out.append({"op": "replace_at_offset_from_choices", "target_offset": int(offc), "token_paths": choices, "source": src})
            "spawn_token_in_inventory":
                var p := String(act.token_path).strip_edges()
                if p != "":
                    var cnt := max(1, int(act.choose_count))
                    if int(act.min_amount) != 0 or int(act.max_amount) != 0:
                        cnt = max(1, _roll_amount(act, ctx))
                    out.append({"op": "spawn_token_in_inventory", "token_path": p, "count": cnt, "source": src})
            "destroy_all_copies_choose":
                # Player chooses a target; executor resolves name and destroys all copies in inventory
                out.append({"op": "destroy_all_copies_choose", "target_kind": "choose", "choose": true, "source": src})
            "spawn_random_by_tag":
                var cnt_tag := max(1, int(act.choose_count))
                out.append({"op": "spawn_random_by_tag", "target_tag": String(tgt.get("target_tag", target_tag)), "count": cnt_tag, "source": src})
            "spawn_random_by_rarity":
                var cnt_r := max(1, int(act.choose_count))
                out.append({"op": "spawn_random_by_rarity", "rarity": String(act.rarity), "count": cnt_r, "source": src})
            "spawn_random_any":
                var cnt_any := max(1, int(act.choose_count))
                out.append({"op": "spawn_random_any", "count": cnt_any, "source": src})
            "spawn_copy_of_last_destroyed":
                var cnt_l := max(1, int(act.choose_count))
                out.append({"op": "spawn_copy_of_last_destroyed", "count": cnt_l, "source": src})
            "permanent_add_from_self_current":
                var self_c := _find_self_contrib(contribs, source_token)
                if self_c.is_empty():
                    continue
                var amt_self := _contrib_value(self_c)
                if amt_self != 0:
                    var cands_pa2 := _collect_candidate_offsets(contribs, source_token, tgt)
                    var picks_pa2 := _choose_offsets(cands_pa2, act, ctx)
                    if picks_pa2.is_empty(): picks_pa2 = [int(tgt.get("target_offset", 0))]
                    for offp2 in picks_pa2:
                        out.append({"op": "permanent_add", "target_kind": "offset", "target_offset": int(offp2), "amount": amt_self, "destroy_if_zero": false, "source": src})
            "destroy_lowest_triggered":
                out.append({"op": "destroy_lowest_triggered", "exclude_self": bool(act.exclude_self), "source": src})
            "destroy_random_triggered_by_rarity_and_gain":
                var rar_s := String(act.rarity)
                out.append({"op": "destroy_random_triggered_by_rarity_and_gain", "rarity": rar_s, "match_any_rarity": bool(act.match_any_rarity), "gain_to_self": bool(act.gain_to_self), "source": src})
            "adjust_empty_rarity_bonus":
                var delta := float(act.factor)
                if abs(delta) <= 0.000001:
                    delta = float(_roll_amount(act, ctx))
                if delta != 0.0:
                    out.append({"op": "adjust_empty_rarity_bonus", "amount": delta, "source": src})
            "guarantee_next_loot_rarity":
                var rar := String(target_tag)
                if rar.strip_edges() == "": rar = String(target_name)
                if rar.strip_edges() != "":
                    var count := max(1, int(_roll_amount(act, ctx)))
                    out.append({"op": "guarantee_next_loot_rarity", "rarity": rar.to_lower(), "count": count, "source": src})
            "add_loot_options_bonus":
                var bonus := int(_roll_amount(act, ctx))
                if bonus != 0:
                    out.append({"op": "add_loot_options_bonus", "amount": bonus, "source": src})
            "restart_round":
                out.append({"op": "restart_round", "source": src})
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

# ---------- on any token destroyed (reactive) ----------
func on_any_token_destroyed(ctx: Dictionary, destroyed_token: Resource, source_token: Resource) -> Array:
    if actions.is_empty():
        return []
    var out: Array = []
    if ctx is Dictionary:
        ctx["last_destroyed_token"] = destroyed_token
    var src := "ability:%s" % String(id)
    for act in actions:
        if act == null: continue
        var op := String(act.op).strip_edges().to_lower()
        var tgt := _resolve_action_target(act)
        # Evaluate conditions using no contribs; ConditionSpec may use ctx.last_destroyed_token
        if not _conditions_pass(ctx, {}, [], source_token, act.conditions):
            continue
        match op:
            "permanent_add":
                var tkp := String(tgt.get("target_kind", _tk_to_string())).to_lower()
                var amt_pa := int(_roll_amount(act, ctx))
                if amt_pa == 0:
                    pass
                elif tkp == "self" or tkp == "winner" or tkp == "middle":
                    out.append({"op": "permanent_add", "target_kind": "self", "amount": amt_pa, "destroy_if_zero": false, "source": src})
                else:
                    out.append({"op": "permanent_add", "target_kind": tkp, "target_offset": int(tgt.get("target_offset", target_offset)), "target_tag": String(tgt.get("target_tag", target_tag)), "target_name": String(tgt.get("target_name", target_name)), "amount": amt_pa, "destroy_if_zero": false, "source": src})
            "permanent_add_from_last_destroyed":
                var d_tok = destroyed_token
                var v_d := 0
                if d_tok != null and (d_tok as Object).has_method("get"):
                    var vv = d_tok.get("value")
                    if vv != null:
                        v_d = int(vv)
                var numer_ld := max(0, int(act.gain_numer))
                var denom_ld := max(1, int(act.gain_denom))
                var amt_ld := int(floor(float(v_d) * float(numer_ld) / float(denom_ld)))
                if amt_ld != 0:
                    out.append({"op": "permanent_add", "target_kind": "self", "amount": amt_ld, "destroy_if_zero": false, "source": src})
            "spawn_copy_of_last_destroyed":
                var cnt_l := max(1, int(act.choose_count))
                out.append({"op": "spawn_copy_of_last_destroyed", "count": cnt_l, "source": src})
            _:
                pass
    if not out.is_empty():
        _mark_emitted(ctx, source_token)
    return out

# Reactive value-change handler using ActionSpec semantics for common patterns
func on_value_changed(ctx: Dictionary, prev_val: int, new_val: int, source_token: Resource = null, target_token: Variant = null, target_contrib: Dictionary = {}, step: Dictionary = {}) -> void:
    if actions.is_empty():
        return
    for act in actions:
        if act == null: continue
        var op := String(act.op).strip_edges().to_lower()
        match op:
            "destroy_on_decrease":
                if target_token == source_token and int(new_val) < int(prev_val):
                    var off := 0
                    if target_contrib is Dictionary:
                        off = int(target_contrib.get("offset", 0))
                    var pend = ctx.get("__pending_commands", [])
                    if not (pend is Array): pend = []
                    (pend as Array).append({"op":"destroy", "target_offset": off})
                    ctx["__pending_commands"] = pend
            "gain_on_adjacent_decrease":
                # If the target lost value and is adjacent to this effect's owner, grant self +|delta|
                if int(new_val) < int(prev_val):
                    var contribs: Array = ctx.get("__last_contribs") if ctx.has("__last_contribs") else []
                    if contribs is Array:
                        var self_c := _find_self_contrib(contribs, source_token)
                        if self_c.is_empty() and target_token != null:
                            self_c = _find_self_contrib(contribs, target_token)
                        if not self_c.is_empty():
                            var self_off := int(self_c.get("offset", 999))
                            var tgt_off := int(target_contrib.get("offset", 999))
                            if abs(tgt_off - self_off) == 1:
                                var delta := int(prev_val) - int(new_val)
                                if delta > 0:
                                    var pend2 = ctx.get("__pending_commands", [])
                                    if not (pend2 is Array): pend2 = []
                                    (pend2 as Array).append({"op":"permanent_add", "target_kind":"self", "amount": delta, "destroy_if_zero": false})
                                    ctx["__pending_commands"] = pend2
            "double_value_change":
                if target_token == source_token:
                    var delta := int(new_val) - int(prev_val)
                    if delta != 0:
                        var fac := max(0.0, float(act.factor))
                        if abs(fac - 1.0) > 0.000001:
                            var extra := int(round(float(delta) * (fac - 1.0)))
                            if target_contrib is Dictionary:
                                target_contrib["delta"] = int(target_contrib.get("delta", 0)) + extra
                                var steps_var = target_contrib.get("steps")
                                if steps_var is Array:
                                    var steps_arr: Array = steps_var
                                    if steps_arr.size() > 0 and typeof(steps_arr[steps_arr.size()-1]) == TYPE_DICTIONARY:
                                        var last: Dictionary = steps_arr[steps_arr.size()-1]
                                        if last.has("after") and typeof(last["after"]) == TYPE_DICTIONARY:
                                            var after: Dictionary = last["after"]
                                            after["delta"] = int(target_contrib.get("delta", 0))
                                            after["val"] = int(new_val) + extra
                                            last["after"] = after
                                        last["add_applied"] = int(last.get("add_applied", 0)) + extra
                                        steps_arr[steps_arr.size()-1] = last
                                        target_contrib["steps"] = steps_arr
            "mirror_change_random":
                if target_token == source_token:
                    var delta_m := int(new_val) - int(prev_val)
                    if delta_m != 0:
                        var contribs: Array = ctx.get("__last_contribs") if ctx.has("__last_contribs") else []
                        if contribs is Array and not contribs.is_empty():
                            var cands: Array[Dictionary] = []
                            for c in contribs:
                                if c is Dictionary and (c as Dictionary).get("token") != source_token:
                                    cands.append(c)
                            if not cands.is_empty():
                                var rng_m := _mk_rng(ctx)
                                var pick: Dictionary = cands[rng_m.randi_range(0, cands.size()-1)]
                                pick["delta"] = int(pick.get("delta", 0)) + int(delta_m)
                                var steps_var2 = pick.get("steps")
                                var steps2: Array = (steps_var2 if steps_var2 is Array else [])
                                steps2.append({"source":"ability:%s" % String(id), "kind":"mirror", "desc":"mirror change", "delta": delta_m})
                                pick["steps"] = steps2
            _:
                pass
