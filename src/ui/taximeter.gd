class_name Taximeter
extends Control

## In-game HUD taximeter displaying shift timer, mode counter (money/score), and delivery side popup.

@export var side_popup_rise: float = 20.0

@onready var _time_title: Label = $TaximeterSprite/TimeTitle
@onready var _time_value: Label = $TaximeterSprite/TimeValue
@onready var _counter_value: Label = $CounterValue
@onready var _counter_label: Label = $CounterLabel
@onready var _side_popup: Label = $SidePopup

var _display_counter: float = 0.0
var _counter_is_money: bool = false
var _counter_format_key: String = ""
var _counter_param: String = ""
var _side_popup_base_pos: Vector2 = Vector2(78.0, 45.0)
var _counter_tween: Tween = null
var _side_popup_tween: Tween = null


func _ready() -> void:
	_side_popup_base_pos = _side_popup.position
	_time_title.text = I18n.t("hud_time")


func configure_counter(info: Dictionary) -> void:
	if info.is_empty():
		return
	_display_counter = float(info["value"])
	_counter_is_money = bool(info["is_money"])
	_counter_format_key = str(info["format_key"])
	_counter_param = str(info["param"])
	_counter_label.text = str(info["label"])
	var color: Color = info["color"] as Color
	_counter_value.add_theme_color_override("font_color", color)
	_counter_label.add_theme_color_override("font_color", color)
	_refresh_counter_label()


func set_time_remaining(seconds: float) -> void:
	var t_rem: int = maxi(0, int(seconds))
	@warning_ignore("integer_division")
	var mins: int = t_rem / 60
	var secs: int = t_rem % 60
	_time_value.text = "%02d:%02d" % [mins, secs]


func tween_counter_to(target_val: float) -> void:
	if _counter_tween != null and _counter_tween.is_valid():
		_counter_tween.kill()
	_counter_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_counter_tween.tween_method(func(v: float) -> void:
		_display_counter = v
		_refresh_counter_label()
	, _display_counter, target_val, 1.0)


func show_side_popup(text: String, color: Color) -> void:
	if _side_popup_tween != null and _side_popup_tween.is_valid():
		_side_popup_tween.kill()
	_side_popup.text = text
	_side_popup.add_theme_color_override("font_color", color)
	_side_popup.position = _side_popup_base_pos
	_side_popup.modulate.a = 0.0
	_side_popup_tween = create_tween()
	_side_popup_tween.tween_property(_side_popup, "modulate:a", 1.0, 0.3)
	_side_popup_tween.parallel().tween_property(_side_popup, "position:y", _side_popup_base_pos.y - side_popup_rise, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_side_popup_tween.tween_interval(1.0)
	_side_popup_tween.tween_property(_side_popup, "modulate:a", 0.0, 0.5)


func _refresh_counter_label() -> void:
	if _counter_format_key.is_empty():
		return
	var formatted_val: String = ("%.2f" % _display_counter) if _counter_is_money else str(int(round(_display_counter)))
	_counter_value.text = I18n.t(_counter_format_key, {_counter_param: formatted_val})
