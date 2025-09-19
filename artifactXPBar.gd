extends Panel
class_name ArtifactXPBar

signal artifact_selection_ready

@export var default_segment_requirements: Array[int] = [4, 4, 4, 4, 5]
@export var segment_gap_px: float = 6.0
@export var empty_segment_color: Color = Color(0.08, 0.08, 0.08, 0.6)
@export var fill_segment_color: Color = Color(0.06, 0.62, 0.36, 1.0)
@export var completed_segment_color: Color = Color(0.09, 0.45, 0.28, 1.0)
@export var border_color: Color = Color(0, 0, 0, 0.85)
@export var border_width_px: float = 1.0

var _segment_schedule: Array[int] = []
var _segment_index: int = 0
var _segment_progress: int = 0

func _ready() -> void:
	_set_segment_schedule(default_segment_requirements)
	if not resized.is_connected(Callable(self, "_on_resized")):
		resized.connect(Callable(self, "_on_resized"))
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		queue_redraw()

func _on_resized() -> void:
	queue_redraw()

func set_segment_schedule(schedule: Array) -> void:
	_set_segment_schedule(schedule)
	reset_bar()

func add_tokens(count: int) -> void:
	if count <= 0 or _segment_schedule.is_empty():
		return
	var remaining: int = count
	while remaining > 0 and not _segment_schedule.is_empty():
		if _segment_index >= _segment_schedule.size():
			break
		var requirement: int = _segment_schedule[_segment_index]
		if requirement <= 0:
			requirement = 1
		var needed: int = requirement - _segment_progress
		if needed <= 0:
			_advance_stage()
			if _segment_schedule.is_empty():
				break
			continue
		var applied: int = remaining
		if applied > needed:
			applied = needed
		_segment_progress += applied
		remaining -= applied
		if _segment_progress >= requirement:
			_advance_stage()
			if _segment_schedule.is_empty():
				break
	queue_redraw()

func reset_bar() -> void:
	_segment_index = 0
	_segment_progress = 0
	queue_redraw()

func total_required_tokens() -> int:
	var total: int = 0
	for req in _segment_schedule:
		total += req
	return total

func tokens_accumulated() -> int:
	var filled: int = _segment_progress
	for i in range(_segment_index):
		filled += _segment_schedule[i]
	return filled

func tokens_remaining_in_current_segment() -> int:
	if _segment_schedule.is_empty() or _segment_index >= _segment_schedule.size():
		return 0
	var remaining: int = _segment_schedule[_segment_index] - _segment_progress
	if remaining < 0:
		remaining = 0
	return remaining

func _draw() -> void:
	if _segment_schedule.is_empty():
		return
	if _segment_index >= _segment_schedule.size():
		return
	var requirement: int = max(1, _segment_schedule[_segment_index])
	var width: float = size.x
	var height: float = size.y
	if width <= 0.0 or height <= 0.0:
		return
	var gap: float = segment_gap_px
	if gap < 0.0:
		gap = 0.0
	var gap_total: float = gap * float(max(requirement - 1, 0))
	var available_width: float = width - gap_total
	if available_width < 0.0:
		available_width = 0.0
	var segment_width: float = 0.0
	if requirement > 0:
		segment_width = available_width / float(requirement)
	var x: float = 0.0
	var progress: float = float(_segment_progress)
	for i in range(requirement):
		var seg_rect: Rect2 = Rect2(Vector2(x, 0.0), Vector2(segment_width, height))
		draw_rect(seg_rect, empty_segment_color, true)
		var fill_ratio: float = progress - float(i)
		if fill_ratio < 0.0:
			fill_ratio = 0.0
		if fill_ratio > 1.0:
			fill_ratio = 1.0
		if fill_ratio > 0.0:
			var fill_rect: Rect2 = Rect2(Vector2(x, 0.0), Vector2(segment_width * fill_ratio, height))
			var color: Color = completed_segment_color if fill_ratio >= 1.0 else fill_segment_color
			draw_rect(fill_rect, color, true)
		if border_width_px > 0.0:
			draw_rect(seg_rect, border_color, false, border_width_px)
		x += segment_width + gap

func _set_segment_schedule(schedule: Array) -> void:
	var sanitized: Array[int] = []
	if schedule != null:
		for value in schedule:
			var req: int = int(value)
			if req > 0:
				sanitized.append(req)
	if sanitized.is_empty():
		sanitized = [1]
	_segment_schedule = sanitized
	_segment_index = clampi(_segment_index, 0, _segment_schedule.size() - 1)
	_segment_progress = clampi(_segment_progress, 0, _segment_schedule[_segment_index])
	queue_redraw()

func _advance_stage() -> void:
	_segment_progress = 0
	_segment_index += 1
	if _segment_index >= _segment_schedule.size():
		print("artifact selection")
		emit_signal("artifact_selection_ready")
		reset_bar()
