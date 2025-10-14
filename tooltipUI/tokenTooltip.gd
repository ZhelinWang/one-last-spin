extends PanelContainer
class_name TokenTooltipView

@export var pixel_font: FontFile   # Optional: assign a pixel/bitmap font in Inspector
@export var base_only: bool = false
# When true, dims the Active description to indicate it won't trigger (e.g., side slots during spin)
@export var force_dim_active: bool = false
@export var force_dim_passive: bool = false
@export var temp_gain_color: Color = Color8(80, 220, 80)
@export var temp_loss_color: Color = Color8(220, 80, 80)

const ACTIVE_TITLE_COLOR := Color8(246, 44, 37)    # #f62c25
const PASSIVE_TITLE_COLOR := Color8(66, 182, 255)  # #42b6ff
const DEFAULT_DESC_COLOR := Color(0.9, 0.9, 0.95)
const DIM_DESC_COLOR := Color(0.6, 0.6, 0.68)
const TAG_BG := Color(0.16, 0.16, 0.2, 0.9)
const TAG_TEXT := Color(0.92, 0.92, 0.96)

var _built := false
var _panel_sb: StyleBoxFlat
var _name_label: Label
var _value_label: Label
var _active_title_label: Label
var _active_desc_label: RichTextLabel
var _passive_title_label: Label
var _passive_desc_label: RichTextLabel
var _tags_separator: HSeparator
var _tags_flow: FlowContainer

# Wrappers to apply 5px top margin to all copy and to toggle visibility cleanly
var _name_wrap: MarginContainer
var _value_wrap: MarginContainer
var _active_title_wrap: MarginContainer
var _active_desc_wrap: MarginContainer
var _passive_title_wrap: MarginContainer
var _passive_desc_wrap: MarginContainer

func _ready() -> void:
	if _built:
		return
	_built = true
	name = "TokenTooltipView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	z_index = 4096
	# Panel style (pixel-friendly, 10px inner padding)
	_panel_sb = StyleBoxFlat.new()
	_panel_sb.bg_color = Color(0.10, 0.10, 0.12, 0.98)
	_panel_sb.set_border_width_all(2)
	_panel_sb.set_corner_radius_all(4)
	_panel_sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", _panel_sb)
	_move_to_tooltip_layer()

	# Root layout
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	# Header: Name (left) + Value (right)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	v.add_child(header)

	_name_label = Label.new()
	_apply_pixel_label_theme(_name_label, 18)
	_name_wrap = _wrap_top_margin(_name_label, 5)
	_name_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name_wrap)

	_value_label = Label.new()
	_apply_pixel_label_theme(_value_label, 14)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_wrap = _wrap_top_margin(_value_label, 5)
	header.add_child(_value_wrap)

	# Separator
	v.add_child(HSeparator.new())

	# Active section
	_active_title_label = Label.new()
	_apply_pixel_label_theme(_active_title_label, 14, ACTIVE_TITLE_COLOR)
	_active_title_label.text = "Active:"
	_active_title_wrap = _wrap_top_margin(_active_title_label, 5)
	v.add_child(_active_title_wrap)

	_active_desc_label = RichTextLabel.new()
	_apply_pixel_rich_theme(_active_desc_label, 13)
	_active_desc_wrap = _wrap_top_margin(_active_desc_label, 0)
	v.add_child(_active_desc_wrap)

	# Passive section
	_passive_title_label = Label.new()
	_apply_pixel_label_theme(_passive_title_label, 14, PASSIVE_TITLE_COLOR)
	_passive_title_label.text = "Passive:"
	_passive_title_wrap = _wrap_top_margin(_passive_title_label, 5)
	v.add_child(_passive_title_wrap)

	_passive_desc_label = RichTextLabel.new()
	_apply_pixel_rich_theme(_passive_desc_label, 13)
	_passive_desc_wrap = _wrap_top_margin(_passive_desc_label, 0)
	v.add_child(_passive_desc_wrap)

	# Bottom separator before tags (shown only if tags exist)
	_tags_separator = HSeparator.new()
	v.add_child(_tags_separator)

	# Tags section (no "Tags:" title; just chips at the bottom)
	_tags_flow = FlowContainer.new()
	_tags_flow.add_theme_constant_override("h_separation", 6)
	_tags_flow.add_theme_constant_override("v_separation", 6)
	

	
	v.add_child(_tags_flow)

func set_data(data: TokenLootData) -> void:
	if data == null:
		return

	# Header
	_name_label.text = data.name
	var curr_val: int = int(data.value)
	var base_val: int = curr_val
	# Resolve stamped base value (property if present, else Resource metadata)
	if data.has_method("get"):
		var has_base_prop := false
		for p in data.get_property_list():
			if String(p.get("name", "")) == "base_value":
				has_base_prop = true
				break
		if has_base_prop:
			var bv = data.get("base_value")
			if bv != null:
				base_val = int(bv)
			elif data.has_meta("base_value"):
				base_val = int(data.get_meta("base_value"))

	var neutral := Color(0.92, 0.92, 0.96)
	var temp_delta: float = 0.0
	var temp_color := neutral
	var has_temp := false
	if data != null and data is Object and (data as Object).has_method("has_meta"):
		if data.has_meta("__temp_spin_delta"):
			temp_delta = float(data.get_meta("__temp_spin_delta"))
			if abs(temp_delta) > 0.001:
				has_temp = true
		if data.has_meta("__temp_spin_color"):
			var col = data.get_meta("__temp_spin_color")
			if col is Color:
				temp_color = col
	if has_temp and temp_color == neutral:
		if temp_delta > 0.0:
			temp_color = temp_gain_color
		elif temp_delta < 0.0:
			temp_color = temp_loss_color
	if base_only:
		_value_label.text = "Value: %d" % base_val
		_value_label.add_theme_color_override("font_color", neutral)
	else:
		if has_temp:
			var temp_str := "%+d" % int(round(temp_delta))
			_value_label.text = "Value: %d (%s)" % [curr_val, temp_str]
			_value_label.add_theme_color_override("font_color", temp_color)
		else:
			_value_label.text = "Value: %d" % curr_val
			if curr_val > base_val:
				_value_label.add_theme_color_override("font_color", temp_gain_color)
			elif curr_val < base_val:
				_value_label.add_theme_color_override("font_color", temp_loss_color)
			else:
				_value_label.add_theme_color_override("font_color", neutral)

	# Rarity via color only (no rarity text)
	var rare_col := data.get_color()
	_name_label.add_theme_color_override("font_color", rare_col)
	if _panel_sb:
		_panel_sb.border_color = rare_col

	# Descriptions (show sections only if non-empty)
	var has_active := false
	var has_passive := false
	if String(data.activeDescription).strip_edges() != "":
		has_active = true
	if String(data.passiveDescription).strip_edges() != "":
		has_passive = true

	_active_title_wrap.visible = has_active
	_active_desc_wrap.visible = has_active
	if has_active:
		_active_desc_label.text = String(data.activeDescription)
		# Apply any requested dimming
		set_dim_active(force_dim_active)
	else:
		_active_desc_label.text = ""

	_passive_title_wrap.visible = has_passive
	_passive_desc_wrap.visible = has_passive
	if has_passive:
		_passive_desc_label.text = String(data.passiveDescription)
	else:
		_passive_desc_label.text = ""
	set_dim_passive(force_dim_passive if has_passive else false)

	# --- Tags with indentation (no title) ---
	# Wrap tags flow in an indented MarginContainer once (idempotent)
	if _tags_flow and _tags_flow.get_parent() and not (_tags_flow.get_parent() is MarginContainer and _tags_flow.get_parent().name == "TagsIndent"):
		var parent := _tags_flow.get_parent()
		var idx := _tags_flow.get_index()
		parent.remove_child(_tags_flow)
		var indent_wrap := MarginContainer.new()
		indent_wrap.name = "TagsIndent"
		indent_wrap.add_theme_constant_override("margin_left", 12) # indent amount
		parent.add_child(indent_wrap)
		parent.move_child(indent_wrap, idx)
		indent_wrap.add_child(_tags_flow)

	# Clear and repopulate tags
	_clear_node_children(_tags_flow)
	var tag_list: PackedStringArray = data.tags

	# Toggle visibility (hide separator and flow when no tags)
	var tags_node: Control = _tags_flow
	if _tags_flow.get_parent() is MarginContainer and _tags_flow.get_parent().name == "TagsIndent":
		tags_node = _tags_flow.get_parent() as Control

	var has_tags := false
	if tag_list.size() > 0:
		has_tags = true

	_tags_separator.visible = has_tags
	tags_node.visible = has_tags

	if has_tags:
		for t in tag_list:
			_tags_flow.add_child(_make_tag_chip(t))

	reset_size()
	queue_redraw()

# ---- Helpers ----

func _apply_pixel_label_theme(lbl: Label, size: int, color: Color = Color(0.92, 0.92, 0.96)) -> void:
	if pixel_font != null:
		lbl.add_theme_font_override("font", pixel_font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_color_override("font_color", color)

func _apply_pixel_rich_theme(rt: RichTextLabel, size: int) -> void:
	rt.fit_content = true
	rt.bbcode_enabled = false
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD
	if pixel_font != null:
		rt.add_theme_font_override("normal_font", pixel_font)
	rt.add_theme_font_size_override("normal_font_size", size)
	rt.modulate = DEFAULT_DESC_COLOR

func _wrap_top_margin(child: Control, px: int) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_top", px)
	mc.add_child(child)
	return mc

func _clear_node_children(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()

func _make_tag_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAG_BG
	sb.set_border_width_all(1)
	sb.border_color = Color(0, 0, 0, 0.9)
	sb.set_corner_radius_all(3)
	sb.set_content_margin(SIDE_LEFT, 6)
	sb.set_content_margin(SIDE_RIGHT, 6)
	sb.set_content_margin(SIDE_TOP, 5)     # 5px top margin for chip text
	sb.set_content_margin(SIDE_BOTTOM, 2)
	chip.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	if pixel_font != null:
		lbl.add_theme_font_override("font", pixel_font)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", TAG_TEXT)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.text = text
	chip.add_child(lbl)
	return chip


func _is_empty_token_data(data: TokenLootData) -> bool:
	if data == null:
		return false
	return String(data.name).strip_edges().to_lower() == "empty"

func _format_empty_passive_desc() -> String:
	var bonus := 0.03
	var root := get_tree().get_root()
	if root != null:
		var cm := root.get_node_or_null("coinManager")
		if cm != null:
			var bonus_var = cm.get("empty_non_common_bonus_per")
			if bonus_var != null:
				bonus = float(bonus_var)
	var percent := bonus * 100.0
	var percent_text := "%0.2f" % percent
	while percent_text.ends_with("0") and percent_text.find(".") != -1:
		percent_text = percent_text.substr(0, percent_text.length() - 1)
	if percent_text.ends_with("."):
		percent_text = percent_text.substr(0, percent_text.length() - 1)
	return "%s%% increased chance for rarer tokens to spawn." % percent_text

func _move_to_tooltip_layer() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var layer := scene.get_node_or_null("TooltipLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "TooltipLayer"
		layer.layer = 200  # must be > overlay (90)
		scene.add_child(layer)

	# Reparent on next frame to avoid tree-modification-in-notification
	call_deferred("_reparent_to_layer", layer)

func _reparent_to_layer(layer: CanvasLayer) -> void:
	if get_parent():
		get_parent().remove_child(self)
	layer.add_child(self)

# Public helper to update dimming dynamically (e.g., as spin phases progress)
func set_dim_active(dim: bool) -> void:
	force_dim_active = dim
	if _active_desc_label == null:
		return
	if dim:
		_active_desc_label.modulate = DIM_DESC_COLOR
	else:
		_active_desc_label.modulate = DEFAULT_DESC_COLOR

func set_dim_passive(dim: bool) -> void:
	force_dim_passive = dim
	if _passive_desc_label == null:
		return
	if dim:
		_passive_desc_label.modulate = DIM_DESC_COLOR
	else:
		_passive_desc_label.modulate = DEFAULT_DESC_COLOR
