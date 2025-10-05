extends GridContainer
class_name ArtifactStrip

@export var max_artifacts: int = 5
@export var icon_size: Vector2i = Vector2i(64, 64)
@export var tile_padding: Vector2i = Vector2i(12, 12)
@export var name_font_size: int = 14
@export var background_color: Color = Color(0.08, 0.08, 0.1, 0.85)
@export var border_color: Color = Color(0.82, 0.12, 0.16)

var _artifacts: Array[ArtifactData] = []

func _ready() -> void:
	if columns <= 0:
		columns = max_artifacts
	_render()

func set_artifacts(artifacts: Array) -> void:
	_artifacts.clear()
	if artifacts == null:
		_render()
		return
	for art in artifacts:
		if art == null:
			continue
		if _artifacts.size() >= max_artifacts:
			break
		_artifacts.append(art)
	_render()

func add_artifact(artifact: ArtifactData) -> void:
	if artifact == null:
		return
	if _artifacts.size() >= max_artifacts:
		return
	var uid := _safe_id(artifact)
	for existing in _artifacts:
		if _safe_id(existing) == uid:
			return
	_artifacts.append(artifact)
	_render()

func remove_artifact(artifact: ArtifactData) -> void:
	if artifact == null:
		return
	var uid := _safe_id(artifact)
	for i in range(_artifacts.size() - 1, -1, -1):
		if _safe_id(_artifacts[i]) == uid:
			_artifacts.remove_at(i)
			break
	_render()

func clear_artifacts() -> void:
	_artifacts.clear()
	_render()

func _render() -> void:
	for child in get_children():
		child.queue_free()
	if _artifacts.is_empty():
		return
	for art in _artifacts:
		_add_artifact_tile(art)

func _add_artifact_tile(artifact: ArtifactData) -> void:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.tooltip_text = ""
	var sb := StyleBoxFlat.new()
	sb.bg_color = background_color
	#sb.set_border_width_all(2)
	var art_color := border_color
	if artifact != null and artifact.has_method("get_color"):
		art_color = artifact.call("get_color")
	sb.border_color = art_color
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	frame.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	frame.add_child(vb)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(icon_size)
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if artifact != null and artifact.has_method("get_icon"):
		icon_rect.texture = artifact.call("get_icon")
	vb.add_child(icon_rect)


	frame.set_meta("token_data", artifact)
	var tip := TooltipSpawner.new()
	tip.name = "TooltipSpawner"
	frame.add_child(tip)

	add_child(frame)

func _safe_id(artifact: ArtifactData) -> String:
	if artifact == null:
		return ""
	if artifact.has_method("get_unique_id"):
		return str(artifact.call("get_unique_id"))
	return str(artifact.get_instance_id())
