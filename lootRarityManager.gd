extends Node
class_name LootRarityManager

signal active_profile_changed(name: String, schedule: LootRaritySchedule)

@export var default_schedule: LootRaritySchedule
@export var profile_names: PackedStringArray = []            # e.g., ["easy", "normal", "hard"]
@export var profiles: Array[LootRaritySchedule] = []         # same order as profile_names
@export var active_profile: String = ""                      # set in editor or at runtime

func _ready() -> void:
	# If no explicit active profile, fall back to default
	if active_profile.strip_edges() == "" and default_schedule != null:
		active_profile = "__default__"

func get_active_schedule() -> LootRaritySchedule:
	if active_profile == "__default__":
		return default_schedule
	# find by name
	for i in range(min(profile_names.size(), profiles.size())):
		if String(profile_names[i]).to_lower() == active_profile.to_lower():
			return profiles[i]
	return default_schedule

func set_active_profile(name: String) -> void:
	active_profile = name
	emit_signal("active_profile_changed", active_profile, get_active_schedule())

func set_active_schedule(schedule: LootRaritySchedule) -> void:
	# Directly assign a specific schedule for advanced cases
	default_schedule = schedule
	active_profile = "__default__"
	emit_signal("active_profile_changed", active_profile, default_schedule)

func get_profile_names() -> PackedStringArray:
	return profile_names.duplicate()
