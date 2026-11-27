class_name PauseMenuModal
extends Control

## In-game pause modal (Continue, optional Skip Tutorial, Options, Main Menu, Quit Game).

signal skip_tutorial_requested

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _title_label: Label = $Panel/TitleLabel
@onready var _btn_resume: Button = $Panel/BtnResume
@onready var _btn_skip_tutorial: Button = $Panel/BtnSkipTutorial
@onready var _btn_options: Button = $Panel/BtnOptions
@onready var _btn_exit: Button = $Panel/BtnExit
@onready var _btn_quit: Button = $Panel/BtnQuit

var _is_exiting: bool = false
var _can_skip_tutorial: bool = false


func set_tutorial_skippable(enabled: bool) -> void:
	_can_skip_tutorial = enabled
	if is_node_ready():
		_layout_buttons()


func _ready() -> void:
	_refresh_texts()

	_btn_resume.pressed.connect(_on_resume)
	_btn_skip_tutorial.pressed.connect(_on_skip_tutorial)
	_btn_options.pressed.connect(_on_options)
	_btn_exit.pressed.connect(_on_exit_menu)
	_btn_quit.pressed.connect(_on_quit)
	_layout_buttons()
	_btn_resume.grab_focus()

	AudioManager.set_music_paused(true)
	AudioManager.set_ambient_paused(true)

	_dim.color.a = 0.0
	_panel.position.y = -220.0
	var target_y: float = (get_viewport_rect().size.y - _panel.size.y) * 0.5
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.5, 0.3)
	tween.tween_property(_panel, "position:y", target_y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _refresh_texts() -> void:
	_title_label.text = I18n.t("pause_title")
	_btn_resume.text = I18n.t("btn_resume")
	_btn_skip_tutorial.text = I18n.t("btn_skip_tutorial")
	_btn_options.text = I18n.t("btn_options")
	_btn_exit.text = I18n.t("btn_exit_menu")
	_btn_quit.text = I18n.t("btn_quit_desktop")


func _layout_buttons() -> void:
	var show_quit: bool = not OS.has_feature("web")
	_btn_skip_tutorial.visible = _can_skip_tutorial
	_btn_skip_tutorial.focus_mode = Control.FOCUS_ALL if _can_skip_tutorial else Control.FOCUS_NONE
	_btn_quit.visible = show_quit
	_btn_quit.focus_mode = Control.FOCUS_ALL if show_quit else Control.FOCUS_NONE

	var y: float = 45.0
	for btn: Button in [_btn_resume, _btn_skip_tutorial, _btn_options, _btn_exit, _btn_quit]:
		if not btn.visible:
			continue
		btn.offset_top = y
		btn.offset_bottom = y + 24.0
		y += 31.0

	var panel_h: float = y + 16.0
	_panel.offset_top = -panel_h * 0.5
	_panel.offset_bottom = panel_h * 0.5
	_panel.size.y = panel_h


func _unhandled_input(event: InputEvent) -> void:
	if GameFlow.get_top_modal() != self:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_resume()


func _on_resume() -> void:
	if _is_exiting:
		return
	_close_and_unpause("unpause")


func _on_skip_tutorial() -> void:
	if _is_exiting:
		return
	skip_tutorial_requested.emit()
	_close_and_unpause("press")


func _close_and_unpause(sfx_key: String) -> void:
	_is_exiting = true
	AudioManager.play_sfx(sfx_key)

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.0, 0.3)
	tween.tween_property(_panel, "position:y", -220.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
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
	opts.closed.connect(_refresh_texts)
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
