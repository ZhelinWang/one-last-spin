extends HBoxContainer

# Simple horizontal inventory strip that displays the player's tokens.
# spinRoot.gd expects this node to expose `set_items(items)`.
# Each item is shown as a small icon using the same TokenLootData icon used by slotItem.

class_name InventoryStrip

@export var icon_size: Vector2i = Vector2i(64, 64)
@export var icon_spacing: int = 8
@export var show_tooltips: bool = true

var _items: Array[TokenLootData] = []

func _ready() -> void:
	custom_minimum_size = Vector2(0, icon_size.y)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", icon_spacing)

func clear_icons() -> void:
	for c in get_children():
		c.queue_free()

func set_items(items: Array) -> void:
	# Accepts Array[TokenLootData]
	_items = []
	for it in items:
		_items.append(it)
	_render()

func _render() -> void:
	clear_icons()
	if _items.is_empty():
		return
	for td in _items:
		if td == null:
			continue
		var tex := td.icon if td.has_method("get") == false else td.icon
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(icon_size)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = tex
		# Attach token data for potential tooltip systems
		icon.set_meta("token_data", td)
		if show_tooltips:
			# If your tooltip system uses TooltipSpawner like slots, add a spawner child
			var tip := TooltipSpawner.new()
			tip.name = "TooltipSpawner"
			icon.add_child(tip)
		add_child(icon)
