extends HBoxContainer

# Simple horizontal inventory strip that displays the player's tokens.
# spinRoot.gd expects this node to expose `set_items(items)`.
# Each item is shown as a small icon using the same TokenLootData icon used by slotItem.

class_name InventoryStrip

@export var icon_size: Vector2i = Vector2i(64, 64)
@export var icon_spacing: int = 8
@export var show_tooltips: bool = true
@export var show_counts: bool = true
@export var count_font_size: int = 14

var _items: Array[TokenLootData] = []
var _counts: Dictionary = {}
var _live_items: Array = []
var _pending_items: Array = []
var _preview_items: Array = []
var _preview_active: bool = false

func _key_for_token(td) -> String:
	# Prefer stable, human-meaningful grouping by lowercase name.
	# Fallback: resource_path, then instance id to avoid collisions when unnamed.
	if td == null:
		return ""
	var nm: String = ""
	if td is TokenLootData:
		nm = (td as TokenLootData).name
	elif td.has_method("get"):
		var v = td.get("name")
		if typeof(v) == TYPE_STRING:
			nm = String(v)
	nm = nm.strip_edges()
	if nm != "":
		return nm.to_lower()
	if td is Resource and td.resource_path != "":
		return String(td.resource_path)
	return str(td.get_instance_id())

func _ready() -> void:
	custom_minimum_size = Vector2(0, icon_size.y)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", icon_spacing)
	if get_parent() is ScrollContainer:
		var sc := get_parent() as ScrollContainer
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
func clear_icons() -> void:
	for c in get_children():
		c.queue_free()

func _clone_items(items: Array) -> Array:
	var out: Array = []
	if items == null:
		return out
	var coin_mgr := get_node_or_null("/root/coinManager")
	for it in items:
		var dup: Variant = it
		if it is Resource:
			var uid := 0
			if coin_mgr != null and coin_mgr.has_method("ensure_token_uid"):
				uid = int(coin_mgr.call("ensure_token_uid", it))
			dup = (it as Resource).duplicate(true)
			if dup != null and uid != 0 and (dup as Object).has_method("set_meta"):
				dup.set_meta("__highlight_uid", uid)
				if (dup as Object).has_method("get_instance_id"):
					dup.set_meta("__highlight_uid_owner", int(dup.get_instance_id()))
		if dup != null:
			out.append(dup)
		else:
			out.append(it)
	return out

func _apply_items(items: Array) -> void:
	_items.clear()
	_counts.clear()
	var coin_mgr := get_node_or_null("/root/coinManager")
	for it in items:
		if it == null:
			continue
		_items.append(it)
		var key := _key_for_token(it)
		_counts[key] = int(_counts.get(key, 0)) + 1
	_render()

func set_items(items: Array) -> void:
	var clone := _clone_items(items)
	if _preview_active:
		_pending_items = clone
		return
	_live_items = clone
	_apply_items(clone)

func begin_preview(items: Array) -> void:
	var clone := _clone_items(items)
	if _preview_active:
		update_preview(items)
		return
	_preview_active = true
	_preview_items = clone
	_apply_items(clone)

func update_preview(items: Array) -> void:
	if not _preview_active:
		begin_preview(items)
		return
	_preview_items = _clone_items(items)
	_apply_items(_preview_items)

func end_preview() -> void:
	_preview_active = false
	_preview_items.clear()
	var to_apply: Array
	if !_pending_items.is_empty():
		to_apply = _pending_items
		_live_items = _pending_items
		_pending_items = []
	else:
		to_apply = _live_items
	_apply_items(_clone_items(to_apply))

func _render() -> void:
	clear_icons()
	if _items.is_empty():
		return
	# Build a stable order of unique tokens (by key)
	var coin_mgr := get_node_or_null("/root/coinManager")
	var seen: Dictionary = {}
	for td in _items:
		if td == null:
			continue
		var key := _key_for_token(td)
		if seen.has(key):
			continue
		seen[key] = td

		# Holder: vertical stack (icon above, count below)
		var holder := VBoxContainer.new()
		holder.name = "TokenHolder"
		holder.add_theme_constant_override("separation", 2)
		var total_h := icon_size.y + count_font_size + 6
		holder.custom_minimum_size = Vector2(icon_size.x, total_h)
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		# Attach token data for tooltip system to read from this control
		holder.set_meta("token_data", td)
		if coin_mgr != null and coin_mgr.has_method("register_token_control"):
			coin_mgr.call("register_token_control", td, holder)
		# Inventory tooltips should show base values only
		holder.set_meta("tooltip_base_only", true)

		# Icon
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(icon_size)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.texture = td.icon
		holder.add_child(icon)

			# Count label (centered; e.g., "1x")
		if show_counts:
			var count := int(_counts.get(key, 1))
			var lbl := Label.new()
			lbl.name = "CountLabel"
			lbl.text = "%dx" % count
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_constant_override("outline_size", 2)
			lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			lbl.add_theme_color_override("font_color", Color.WHITE)
			lbl.add_theme_font_size_override("font_size", count_font_size)
			holder.add_child(lbl)

		# Tooltip spawner on the holder (covers icon+label)
		if show_tooltips:
			if holder.get_node_or_null("TooltipSpawner") == null:
				var tip := TooltipSpawner.new()
				tip.name = "TooltipSpawner"
				holder.add_child(tip)

		add_child(holder)
