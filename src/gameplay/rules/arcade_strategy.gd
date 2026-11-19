class_name ArcadeStrategy
extends RuleStrategy

## Arcade mode: race the clock, gaining bonus time and points for fast/safe deliveries.

var passengers_delivered: int = 0
var score: int = 0


func _init(p_start_time: float = GameConstants.ARCADE_START_TIME) -> void:
	mode_id = "arcade"
	has_timer = true
	has_hud = true
	time_remaining = p_start_time


func get_start_text() -> String:
	return I18n.t("mode_arcade_initial_text")


func update_rule(delta: float) -> void:
	if game_over:
		return
	time_remaining -= delta
	if time_remaining <= 0.0:
		time_remaining = 0.0
		game_over = true


func on_passenger_delivered(passenger: Passenger, distance: float) -> Dictionary:
	passengers_delivered += 1
	var time_gained: float = GameConstants.ARCADE_BASE_TIME_GAIN
	var score_gained: int = GameConstants.ARCADE_BASE_SCORE
	var b: Dictionary = RuleStrategy.evaluate_delivery_bonuses(passenger, distance)
	var fast: bool = bool(b["fast"])
	var safe: bool = bool(b["safe"])
	if fast:
		time_gained += GameConstants.ARCADE_FAST_TIME_GAIN
		score_gained += GameConstants.ARCADE_TIME_BONUS_SCORE
	if safe:
		time_gained += GameConstants.ARCADE_SAFETY_TIME_GAIN
		score_gained += GameConstants.ARCADE_SAFETY_BONUS_SCORE

	time_remaining += time_gained
	score += score_gained

	var side_text: String = ("+%d pts" % score_gained) + str(b["suffix"])

	return {
		"center_popup": "+%ds" % int(time_gained),
		"center_color": GameConstants.UI_GOLD,
		"side_popup": side_text,
		"side_color": GameConstants.UI_GOLD,
		"bonus": fast or safe,
		"tween_target": float(score),
	}


func get_hud_counter_text() -> Dictionary:
	return {
		"value": float(score),
		"format_key": "hud_score_value",
		"param": "score",
		"is_money": false,
		"label": I18n.t("hud_score_label"),
		"color": GameConstants.UI_AMBER,
	}


func evaluate_end(taxi_health: float) -> Dictionary:
	var reason: String = I18n.t("game_over_time_up") if time_remaining <= 0.0 else I18n.t("game_over_destroyed")
	if taxi_health <= 0.0:
		reason = I18n.t("game_over_destroyed")
	return {
		"action": "game_over",
		"reason": reason,
		"mode": "arcade",
		"score": score,
		"record_data": check_record_eligibility("arcade", float(score)),
	}
