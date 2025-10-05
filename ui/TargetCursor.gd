extends Control

@export var count: int = 1
@export var square_size: int = 64
@export var border_thickness: int = 8
@export var color: Color = Color8(246, 44, 37)
@export var text_color: Color = Color(1, 1, 1)
@export var text_padding: int = 6

@onready var _label: Label = $CountLabel

var _mouse_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)
    z_index = 10000
    set_process(true)
    _apply_label()

func set_count(n: int) -> void:
    count = max(1, n)
    _apply_label()

func _apply_label() -> void:
    if _label == null:
        return
    _label.text = "x%d" % count
    _label.add_theme_color_override("font_color", text_color)
    # Ensure reasonable font size; will use theme default font
    var fs := 22
    _label.add_theme_font_size_override("font_size", fs)

func _process(_dt: float) -> void:
    var vp := get_viewport()
    if vp == null:
        return
    _mouse_pos = vp.get_mouse_position()
    # Position label at the square's top-right with padding
    var tl := _mouse_pos - Vector2(square_size * 0.5, square_size * 0.5)
    _label.size = Vector2(square_size - text_padding * 2, 28)
    _label.position = tl + Vector2(text_padding, text_padding)
    _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    queue_redraw()

func _draw() -> void:
    var tl := _mouse_pos - Vector2(square_size * 0.5, square_size * 0.5)
    var rect := Rect2(tl, Vector2(square_size, square_size))
    # Draw unfilled rectangle with thick border
    draw_rect(rect, color, false, float(border_thickness))

