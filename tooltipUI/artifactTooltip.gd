extends PanelContainer
class_name ArtifactTooltipView

@export var pixel_font: FontFile
@export var title_color: Color = Color8(232, 76, 76)
@export var body_color: Color = Color8(238, 238, 240)
@export var accent_color: Color = Color8(255, 160, 160)
@export var flavor_color: Color = Color8(210, 210, 230)

var _built := false
var _panel_sb: StyleBoxFlat
var _name_label: Label
var _desc_label: RichTextLabel
var _detail_label: RichTextLabel
var _flavor_label: RichTextLabel

func _ready() -> void:
	if _built:
		return
	_built = true
	name = "ArtifactTooltipView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	z_index = 4096

	_panel_sb = StyleBoxFlat.new()
	_panel_sb.bg_color = Color(0.1, 0.08, 0.09, 0.98)
	_panel_sb.set_border_width_all(2)
	_panel_sb.border_color = title_color
	_panel_sb.set_corner_radius_all(4)
	_panel_sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", _panel_sb)

	_move_to_tooltip_layer()

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(260, 0)
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	_name_label = Label.new()
	_apply_label_theme(_name_label, 18, title_color)
	v.add_child(_wrap_margin(_name_label, 4))

	_desc_label = RichTextLabel.new()
	_apply_rich_theme(_desc_label, 13, body_color, false)
	v.add_child(_wrap_margin(_desc_label, 0))

	_detail_label = RichTextLabel.new()
	_apply_rich_theme(_detail_label, 12, accent_color, false)
	v.add_child(_wrap_margin(_detail_label, 4))

	_flavor_label = RichTextLabel.new()
	_apply_rich_theme(_flavor_label, 11, flavor_color, true)
	v.add_child(_wrap_margin(_flavor_label, 4))

func set_data(artifact: ArtifactData) -> void:
	if artifact == null:
		return
	_name_label.text = artifact.call("get_display_name")
	_desc_label.text = artifact.call("get_description")
	var details := String(artifact.call("get_tooltip_details"))
	_detail_label.text = details
	_detail_label.visible = details.strip_edges() != ""
	var flavor := String(artifact.call("get_flavor_text"))
	if flavor.strip_edges() != "":
		_flavor_label.text = "[i]%s[/i]" % flavor
		_flavor_label.visible = true
	else:
		_flavor_label.text = ""
		_flavor_label.visible = false
	_panel_sb.border_color = artifact.call("get_color") if artifact.has_method("get_color") else title_color
	reset_size()
	queue_redraw()

func _apply_label_theme(lbl: Label, size: int, color: Color) -> void:
	if pixel_font != null:
		lbl.add_theme_font_override("font", pixel_font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))

func _apply_rich_theme(rt: RichTextLabel, size: int, color: Color, use_bbcode: bool) -> void:
	rt.fit_content = true
	rt.bbcode_enabled = use_bbcode
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD
	if pixel_font != null:
		rt.add_theme_font_override("normal_font", pixel_font)
	rt.add_theme_font_size_override("normal_font_size", size)
	rt.modulate = color

func _wrap_margin(child: Control, top_px: int) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_top", top_px)
	mc.add_child(child)
	return mc

func _move_to_tooltip_layer() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var layer := scene.get_node_or_null("TooltipLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "TooltipLayer"
		layer.layer = 200
		scene.add_child(layer)
	call_deferred("_reparent_to_layer", layer)

func _reparent_to_layer(layer: CanvasLayer) -> void:
	if get_parent():
		get_parent().remove_child(self)
	layer.add_child(self)
