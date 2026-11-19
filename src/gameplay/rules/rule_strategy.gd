class_name RuleStrategy
extends RefCounted

## Base strategy defining scoring, timers, passenger respawn, and game-over rules per mode.

var mode_id: String = ""
var invincible: bool = false
var always_vibe: bool = false
var has_timer: bool = false
var has_hud: bool = true
var time_remaining: float = 0.0
var game_over: bool = false


func get_start_text() -> String:
	return ""


func update_rule(_delta: float) -> void:
	pass


func should_respawn_passengers(_current_count: int) -> bool:
	return false


func on_passenger_delivered(_passenger: Passenger, _distance: float) -> Dictionary:
	return {}


func evaluate_end(_taxi_health: float) -> Dictionary:
	return {"action": "game_over", "reason": "", "mode": mode_id, "score": 0, "record_data": {}}


func get_hud_counter_text() -> Dictionary:
	return {}


static func evaluate_delivery_bonuses(passenger: Passenger, distance: float) -> Dictionary:
	var expected_time: float = maxf(5.0, distance / 100.0)
	var fast: bool = passenger.time_riding < expected_time * 0.8
	var safe: bool = passenger.damage_taken <= 0.0
	var reasons: PackedStringArray = PackedStringArray()
	if fast:
		reasons.append(I18n.t("bonus_fast"))
	if safe:
		reasons.append(I18n.t("bonus_safe"))
	var suffix: String = ("\n(%s)" % ", ".join(reasons)) if not reasons.is_empty() else ""
	return {"fast": fast, "safe": safe, "suffix": suffix}


static func record_new_score(mode_key: String, raw_name: String, score_val: int, existing_records: Dictionary = {}) -> Dictionary:
	var records: Dictionary = existing_records.duplicate(true)
	if records.is_empty():
		records = SaveManager.load_slot("records", {"workday": [], "arcade": []})
	var player_name: String = raw_name.strip_edges()
	if player_name.is_empty():
		player_name = "Unknown"
	if not records.has(mode_key) or not (records[mode_key] is Array):
		records[mode_key] = []
	var list: Array = records[mode_key] as Array
	list.append({"name": player_name, "score": score_val})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0)) > float(b.get("score", 0))
	)
	if list.size() > GameConstants.MAX_RECORDS_PER_MODE:
		list.resize(GameConstants.MAX_RECORDS_PER_MODE)
	records[mode_key] = list
	SaveManager.save_slot("records", records)
	return records


static func check_record_eligibility(mode_key: String, score_val: float) -> Dictionary:
	if score_val <= 0.0:
		return {}
	var records: Dictionary = SaveManager.load_slot("records", {"workday": [], "arcade": []})
	var mode_list: Array = records.get(mode_key, []) as Array
	if mode_list.size() < GameConstants.MAX_RECORDS_PER_MODE:
		return {"mode": mode_key, "score": score_val, "records": records}
	var lowest: float = float((mode_list[mode_list.size() - 1] as Dictionary).get("score", 0))
	if score_val > lowest:
		return {"mode": mode_key, "score": score_val, "records": records}
	return {}
