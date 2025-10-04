extends Resource
class_name ArtifactData

# Base class for artifacts. Each artifact can contribute cosmetic metadata used by the UI
# in addition to spin-time behaviour (delivered by build_steps/applies in future).

@export var effect_name: String = "Unnamed Artifact"
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = load("res://placehold.jpg")
@export var unique_id: String = ""
@export var priority: int = 100
@export var border_color: Color = Color(0.82, 0.12, 0.16, 1.0)
@export_multiline var tooltip_details: String = ""
@export_multiline var flavor_text: String = ""

func get_display_name() -> String:
	var clean := display_name.strip_edges()
	if clean != "":
		return clean
	return effect_name.strip_edges()

func get_description() -> String:
	return description

func get_color() -> Color:
	return border_color

func get_icon() -> Texture2D:
	return icon

func get_unique_id() -> String:
	var clean := unique_id.strip_edges()
	if clean != "":
		return clean
	return get_display_name().to_lower().replace(" ", "_")

func get_tooltip_details() -> String:
	return tooltip_details

func get_flavor_text() -> String:
	return flavor_text

func applies(ctx: Dictionary, contrib: Dictionary) -> bool:
	return true

func build_steps(ctx: Dictionary, contrib: Dictionary) -> Array:
	return []
