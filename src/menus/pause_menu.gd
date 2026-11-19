class_name PauseMenuModal
extends Control

## In-game pause modal (Continue, Options, Main Menu, Quit Game).

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _title_label: Label = $Panel/TitleLabel
@onready var _btn_resume: Button = $Panel/BtnResume
@onready var _btn_options: Button = $Panel/BtnOptions
@onready var _btn_exit: Button = $Panel/BtnExit
@onready var _btn_quit: Button = $Panel/BtnQuit

var _is_exiting: bool = false


func _ready() -> void:
	_title_label.text = I18n.t("pause_title")
	_btn_resume.text = I18n.t("btn_resume")
	_btn_options.text = I18n.t("btn_options")
	_btn_exit.text = I18n.t("btn_exit_menu")
	_btn_quit.text = I18n.t("btn_quit_desktop")

	_btn_resume.pressed.connect(_on_resume)
	_btn_options.pressed.connect(_on_options)
	_btn_exit.pressed.connect(_on_exit_menu)
	_btn_quit.pressed.connect(_on_quit)
	if OS.has_feature("web"):
		_btn_quit.visible = false
		_btn_quit.focus_mode = Control.FOCUS_NONE
	_btn_resume.grab_focus()

	AudioManager.set_music_paused(true)
	AudioManager.set_ambient_paused(true)

	_dim.color.a = 0.0
	_panel.position.y = -200.0
	var target_y: float = (get_viewport_rect().size.y - _panel.size.y) * 0.5
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.5, 0.3)
	tween.tween_property(_panel, "position:y", target_y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if GameFlow.get_top_modal() != self:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_resume()


func _on_resume() -> void:
	if _is_exiting:
		return
	_is_exiting = true
	AudioManager.play_sfx("unpause")

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.0, 0.3)
	tween.tween_property(_panel, "position:y", -200.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		AudioManager.set_music_paused(false)
		AudioManager.set_ambient_paused(false)
		GameFlow.pop_modal(self)
	)


func _on_options() -> void:
	if _is_exiting:
		return
	AudioManager.play_sfx("press")
	var opts: OptionsMenuModal = (load("res://src/menus/options_menu.tscn") as PackedScene).instantiate() as OptionsMenuModal
	opts.closed.connect(func() -> void:
		_title_label.text = I18n.t("pause_title")
		_btn_resume.text = I18n.t("btn_resume")
		_btn_options.text = I18n.t("btn_options")
		_btn_exit.text = I18n.t("btn_exit_menu")
		_btn_quit.text = I18n.t("btn_quit_desktop")
	)
	GameFlow.push_modal(opts, true)


func _on_exit_menu() -> void:
	if _is_exiting:
		return
	_is_exiting = true
	AudioManager.play_sfx("press")
	AudioManager.stop_gameplay_audio()
	GameFlow.change_scene("res://src/menus/title_screen.tscn", 0.5, 0.5)


func _on_quit() -> void:
	AudioManager.play_sfx("press")
	get_tree().quit()
