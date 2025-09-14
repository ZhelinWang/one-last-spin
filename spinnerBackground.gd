extends Panel

@onready var mat: ShaderMaterial = material as ShaderMaterial
var time: float = 0.0

func _ready() -> void:
	mat.set_shader_parameter("resolution", size)

func _process(delta: float) -> void:
	time += delta
	mat.set_shader_parameter("time", time)

func create_ripple(global_pos: Vector2) -> void:
	var local_pos = global_pos - global_position
	var uv = local_pos / size
	mat.set_shader_parameter("ripple_center", uv)
	mat.set_shader_parameter("ripple_start", time)
