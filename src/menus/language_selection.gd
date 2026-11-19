class_name LanguageSelectionModal
extends Control

## Language selection modal supporting English and Spanish.

signal closed

var standalone_mode: bool = false

@onready var _bg_gradient: TextureRect = $BgGradient
@onready var _content: VBoxContainer = $Content
@onready var _title_label: Label = $Content/TitleLabel
@onready var _buttons_box: VBoxContainer = $Content/ButtonsBox

var _is_exiting: bool = false


func _ready() -> void:
	_bg_gradient.visible = standalone_mode
	_title_label.text = I18n.t("msg_lang_title")

	var first_btn: Button = null
	for lang_code in I18n.get_available_languages():
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(150.0, 30.0)
		btn.text = I18n.get_language_name(lang_code)
		btn.pressed.connect(_select_language.bind(lang_code))
		_buttons_box.add_child(btn)
		if first_btn == null:
			first_btn = btn

	if first_btn != null:
		first_btn.grab_focus()

	var vh: float = get_viewport_rect().size.y
	_content.position.y = vh + 120.0
	var target_y: float = (vh - _content.size.y) * 0.5
	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_content, "position:y", target_y, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if standalone_mode or GameFlow.get_top_modal() != self:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_close_modal()


func _select_language(lang_code: String) -> void:
	if _is_exiting:
		return
	I18n.set_language(lang_code)
	_close_modal()


func _close_modal() -> void:
	if _is_exiting:
		return
	_is_exiting = true
	AudioManager.play_sfx("press")

	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_content, "position:y", get_viewport_rect().size.y + 140.0, 0.3)
	tween.tween_callback(func() -> void:
		GameFlow.pop_modal(self)
		closed.emit()
	)
