class_name WorkdayStrategy
extends RuleStrategy

## Workday mode: earn fares in 120s to pay escalating daily fees and repair your taxi.

var day: int = 1
var money: float = 0.0
var fee: float = GameConstants.WORKDAY_BASE_FEE
var is_loaded_run: bool = false


func _init(p_time_limit: float = GameConstants.WORKDAY_TIME_LIMIT, p_money: float = 0.0, p_day: int = 1, p_loaded: bool = false) -> void:
	mode_id = "workday"
	has_timer = true
	has_hud = true
	time_remaining = p_time_limit
	money = p_money
	day = p_day
	is_loaded_run = p_loaded
	fee = GameConstants.WORKDAY_BASE_FEE + float(day - 1) * GameConstants.WORKDAY_FEE_INCREMENT


func get_start_text() -> String:
	return I18n.t("mode_workday_initial_text", {"day": day, "fee": "%.2f" % fee})


func update_rule(delta: float) -> void:
	if game_over:
		return
	time_remaining -= delta
	if time_remaining <= 0.0:
		time_remaining = 0.0
		game_over = true


func on_passenger_delivered(passenger: Passenger, distance: float) -> Dictionary:
	var earned: float = GameConstants.WORKDAY_BASE_FARE + (distance / 100.0)
	var b: Dictionary = RuleStrategy.evaluate_delivery_bonuses(passenger, distance)
	var fast: bool = bool(b["fast"])
	var safe: bool = bool(b["safe"])
	if fast:
		earned += GameConstants.WORKDAY_FAST_BONUS
	if safe:
		earned += GameConstants.WORKDAY_SAFETY_BONUS

	money += earned
	var side_text: String = ("+$%.2f" % earned) + str(b["suffix"])

	return {
		"side_popup": side_text,
		"side_color": Color(0.2, 1.0, 0.2),
		"bonus": fast or safe,
		"tween_target": money,
	}


func get_hud_counter_text() -> Dictionary:
	return {
		"value": money,
		"format_key": "hud_money_value",
		"param": "money",
		"is_money": true,
		"label": I18n.t("hud_money_label"),
		"color": GameConstants.UI_GREEN,
	}


func evaluate_end(taxi_health: float) -> Dictionary:
	if taxi_health <= 0.0:
		if is_loaded_run:
			SaveManager.delete_slot("workday_save")
		return {
			"action": "game_over",
			"reason": I18n.t("game_over_destroyed"),
			"mode": "workday",
			"score": day,
			"record_data": check_record_eligibility("workday", float(day)),
		}

	if money >= fee:
		money -= fee
		return {
			"action": "end_of_day",
			"money": money,
			"health": taxi_health,
			"day": day,
			"is_loaded_run": is_loaded_run,
		}

	if is_loaded_run:
		SaveManager.delete_slot("workday_save")
	return {
		"action": "game_over",
		"reason": I18n.t("game_over_fee_failed", {"fee": "%.2f" % fee}),
		"mode": "workday",
		"score": day,
		"record_data": check_record_eligibility("workday", float(day)),
	}
