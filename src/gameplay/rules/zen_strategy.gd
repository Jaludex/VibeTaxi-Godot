class_name ZenStrategy
extends RuleStrategy

## Zen mode: invincible, permanent Vibe Mode, endless relaxed driving.


func _init() -> void:
	mode_id = "zen"
	invincible = true
	always_vibe = true
	has_timer = false
	has_hud = false


func get_start_text() -> String:
	return I18n.t("mode_zen_initial_text")


func should_respawn_passengers(current_count: int) -> bool:
	return current_count < 3
