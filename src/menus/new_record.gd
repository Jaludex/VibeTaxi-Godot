class_name NewRecordModal
extends Control

## New High Score modal using native LineEdit (allows typing W/A/S/D/X properly).

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _title_label: Label = $Panel/TitleLabel
@onready var _score_label: Label = $Panel/ScoreLabel
@onready var _name_input: LineEdit = $Panel/NameInput
@onready var _btn_submit: Button = $Panel/BtnSubmit

var _mode: String = "arcade"
var _score: float = 0.0
var _records: Dictionary = {}
var _is_exiting: bool = false


func setup(record_data: Dictionary) -> void:
	_mode = str(record_data.get("mode", "arcade"))
	_score = float(record_data.get("score", 0.0))
	_records = (record_data.get("records", {"workday": [], "arcade": []}) as Dictionary).duplicate(true)


var _entered: bool = false


func _ready() -> void:
	_title_label.text = I18n.t("new_record_title")
	_title_label.add_theme_color_override("font_color", GameConstants.UI_GOLD)
	var score_str: String = str(int(_score))
	_score_label.text = I18n.t("new_record_score", {"score": score_str})
	_btn_submit.text = I18n.t("btn_submit")

	_btn_submit.pressed.connect(_on_submit)
	_name_input.text_submitted.connect(func(_t: String) -> void: _on_submit())
	_name_input.grab_focus()

	_dim.color.a = 0.0
	_panel.position.y = -240.0
	var target_y: float = (get_viewport_rect().size.y - _panel.size.y) * 0.5
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 180.0 / 255.0, 0.3)
	tween.tween_property(_panel, "position:y", target_y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void:
		_entered = true
		_name_input.grab_focus()
	)


func _process(delta: float) -> void:
	if not _entered or _is_exiting:
		return
	var vp_h: float = get_viewport_rect().size.y
	var desired_y: float = (vp_h - _panel.size.y) * 0.5
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var kb_h: int = DisplayServer.virtual_keyboard_get_height()
		if kb_h > 0:
			var win_h: float = maxf(1.0, float(DisplayServer.window_get_size().y))
			var kb_vp: float = float(kb_h) * (vp_h / win_h)
			desired_y = maxf(8.0, minf(desired_y, vp_h - kb_vp - _panel.size.y - 12.0))
	_panel.position.y = lerpf(_panel.position.y, desired_y, minf(1.0, delta * 12.0))


func _on_submit() -> void:
	if _is_exiting:
		return
	_is_exiting = true
	AudioManager.play_sfx("press")

	RuleStrategy.record_new_score(_mode, _name_input.text, int(_score), _records)

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.0, 0.3)
	tween.tween_property(_panel, "position:y", -240.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		GameFlow.change_scene("res://src/menus/title_screen.tscn", 0.4, 0.5)
	)
