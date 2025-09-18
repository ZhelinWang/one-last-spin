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

func set_items(items: Array) -> void:
	# Accepts Array[TokenLootData]
	_items.clear()
	_counts.clear()

	# Aggregate by resource path if available; else by instance id
	for it in items:
		if it == null:
			continue
		_items.append(it)
		var key := _key_for_token(it)
		_counts[key] = int(_counts.get(key, 0)) + 1
	_render()

func _render() -> void:
	clear_icons()
	if _items.is_empty():
		return
	# Build a stable order of unique tokens (by key)
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
