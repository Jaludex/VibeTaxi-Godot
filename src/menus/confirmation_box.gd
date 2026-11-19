class_name ConfirmationBoxModal
extends Control

## Modal Yes/No confirmation dialog.

signal confirmed
signal canceled

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _msg_label: Label = $Panel/MsgLabel
@onready var _btn_yes: Button = $Panel/BtnYes
@onready var _btn_no: Button = $Panel/BtnNo

var _message: String = ""
var _is_exiting: bool = false


func setup(message: String) -> void:
	_message = message


func _ready() -> void:
	_msg_label.text = _message
	_btn_yes.text = I18n.t("btn_yes")
	_btn_no.text = I18n.t("btn_no")

	_btn_yes.pressed.connect(_close_with.bind(true))
	_btn_no.pressed.connect(_close_with.bind(false))
	_btn_no.grab_focus()

	_dim.color.a = 0.0
	_panel.position.y = -200.0
	var target_y: float = (get_viewport_rect().size.y - _panel.size.y) * 0.5
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 180.0 / 255.0, 0.3)
	tween.tween_property(_panel, "position:y", target_y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if GameFlow.get_top_modal() != self:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_close_with(false)


func _close_with(is_confirmed: bool) -> void:
	if _is_exiting:
		return
	_is_exiting = true
	AudioManager.play_sfx("press")

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.0, 0.3)
	tween.tween_property(_panel, "position:y", -200.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		GameFlow.pop_modal(self)
		if is_confirmed:
			confirmed.emit()
		else:
			canceled.emit()
	)
