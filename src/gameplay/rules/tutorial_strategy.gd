class_name TutorialStrategy
extends RuleStrategy

## Tutorial mode: invincible guided lessons on the dedicated tutorial map.

var passengers_delivered: int = 0


func _init() -> void:
	mode_id = "tutorial"
	invincible = true
	always_vibe = false
	has_timer = false
	has_hud = true


func get_start_text() -> String:
	return I18n.t("tutorial_start_text")


func on_passenger_delivered(_passenger: Passenger, _distance: float) -> Dictionary:
	passengers_delivered += 1
	return {}
