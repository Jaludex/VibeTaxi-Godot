class_name ModeSelectionModal
extends Control

## Mode selection modal sliding from bottom (Tutorial, Workday, Arcade, Zen).

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _title_label: Label = $Panel/TitleLabel
@onready var _desc_label: Label = $Panel/DescLabel
@onready var _btn_close: Button = $Panel/BtnClose
@onready var _btn_tutorial: Button = $Panel/BtnTutorial
@onready var _btn_workday: Button = $Panel/BtnWorkday
@onready var _btn_arcade: Button = $Panel/BtnArcade
@onready var _btn_zen: Button = $Panel/BtnZen

var _is_exiting: bool = false


func _ready() -> void:
	_title_label.text = I18n.t("mode_selection_title")
	_desc_label.text = I18n.t("mode_selection_title")
	_btn_tutorial.text = I18n.t("btn_tutorial")
	_btn_workday.text = I18n.t("btn_workday")
	_btn_arcade.text = I18n.t("btn_arcade")
	_btn_zen.text = I18n.t("btn_zen")

	_btn_tutorial.pressed.connect(_select_mode.bind("tutorial"))
	_btn_workday.pressed.connect(_select_mode.bind("workday"))
	_btn_arcade.pressed.connect(_select_mode.bind("arcade"))
	_btn_zen.pressed.connect(_select_mode.bind("zen"))
	_btn_close.pressed.connect(_close_modal)

	_wire_desc(_btn_tutorial, "mode_tutorial_desc")
	_wire_desc(_btn_workday, "mode_workday_desc")
	_wire_desc(_btn_arcade, "mode_arcade_desc")
	_wire_desc(_btn_zen, "mode_zen_desc")

	_btn_tutorial.grab_focus()

	_dim.color.a = 0.0
	var vh: float = get_viewport_rect().size.y
	_panel.position.y = vh + 100.0
	var target_y: float = (vh - _panel.size.y) * 0.5
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 180.0 / 255.0, 0.5)
	tween.tween_property(_panel, "position:y", target_y, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if GameFlow.get_top_modal() != self:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_close_modal()


func _wire_desc(btn: Button, key: String) -> void:
	btn.mouse_entered.connect(func() -> void: _desc_label.text = I18n.t(key))
	btn.focus_entered.connect(func() -> void: _desc_label.text = I18n.t(key))


func _select_mode(mode: String) -> void:
	if _is_exiting:
		return
	_is_exiting = true
	AudioManager.play_sfx("press")
	AudioManager.stop_music()
	GameFlow.start_gameplay(mode)


func _close_modal() -> void:
	if _is_exiting:
		return
	_is_exiting = true
	AudioManager.play_sfx("press")
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.0, 0.4)
	tween.tween_property(_panel, "position:y", get_viewport_rect().size.y + 100.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void: GameFlow.pop_modal(self))
