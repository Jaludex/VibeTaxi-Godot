class_name MessageBoxModal
extends Control

## Modal dialog box with paginated TypewriterBox and slide-in/out animation.

signal closed

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _title_label: Label = $Panel/TitleLabel
@onready var _typewriter: TypewriterBox = $Panel/TypewriterBox
@onready var _btn_ok: Button = $Panel/BtnOk

var _is_exiting: bool = false
var _title_text: String = ""
var _msg_text: String = ""


func setup(title_str: String, msg_str: String) -> void:
	_title_text = title_str
	_msg_text = msg_str


func _ready() -> void:
	_title_label.text = _title_text
	_typewriter.set_box_text(_msg_text)
	_btn_ok.pressed.connect(_on_button_pressed)
	_btn_ok.grab_focus()

	_dim.color.a = 0.0
	var target_y: float = (get_viewport_rect().size.y - _panel.size.y) * 0.5
	_panel.position.y = -200.0

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 180.0 / 255.0, 0.3)
	tween.tween_property(_panel, "position:y", target_y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if GameFlow.get_top_modal() != self:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_on_button_pressed()


func _process(_delta: float) -> void:
	_btn_ok.text = I18n.t("btn_next") if _typewriter.has_next_page() else I18n.t("btn_ok")


func _on_button_pressed() -> void:
	if _is_exiting:
		return
	if _typewriter.is_typing or _typewriter.has_next_page():
		_typewriter.advance()
		return
	_close_modal()


func _close_modal() -> void:
	if _is_exiting:
		return
	_is_exiting = true
	AudioManager.play_sfx("press")

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.0, 0.3)
	tween.tween_property(_panel, "position:y", -200.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		GameFlow.pop_modal(self)
		closed.emit()
	)
