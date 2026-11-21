extends Node2D

## Main title screen with live panning city background, menu actions, and modal submenus.

@onready var _city_map: CityMap = $CityMap
@onready var _traffic_system: TrafficSystem = $TrafficSystem
@onready var _pedestrian_system: PedestrianSystem = $PedestrianSystem
@onready var _camera: Camera2D = $Camera2D
@onready var _scene_fade: ColorRect = $UILayer/SceneFade
@onready var _title_label: Label = $UILayer/TitleLabel
@onready var _hint_label: Label = $UILayer/HintLabel
@onready var _version_label: Label = $UILayer/VersionLabel

@onready var _btn_new: Button = $UILayer/ButtonsRoot/BtnNewGame
@onready var _btn_resume: Button = $UILayer/ButtonsRoot/BtnResume
@onready var _btn_records: Button = $UILayer/ButtonsRoot/BtnRecords
@onready var _btn_credits: Button = $UILayer/ButtonsRoot/BtnCredits
@onready var _btn_quit: Button = $UILayer/ButtonsRoot/BtnQuit
@onready var _btn_tutorial: Button = $UILayer/ButtonsRoot/BtnTutorial
@onready var _btn_user_tracks: Button = $UILayer/ButtonsRoot/BtnUserTracks
@onready var _btn_options: Button = $UILayer/ButtonsRoot/BtnOptions

var _positions: Array[Vector2] = []
var _pan_tween: Tween = null


func _ready() -> void:
	_city_map.muted = true
	_city_map.load_map("city", false)
	_traffic_system.setup(_city_map)
	_traffic_system.camera_ref = _camera
	_pedestrian_system.setup(_city_map, _traffic_system)
	_pedestrian_system.camera_ref = _camera

	var rect: Rect2 = _city_map.get_map_rect()
	_camera.limit_left = int(rect.position.x)
	_camera.limit_top = int(rect.position.y)
	_camera.limit_right = int(rect.end.x)
	_camera.limit_bottom = int(rect.end.y)

	_positions = _city_map.get_all_node_positions()
	if _positions.is_empty():
		_positions = [rect.size * 0.25, rect.size * 0.5, rect.size * 0.75]
	_camera.global_position = _positions[randi() % _positions.size()]

	_btn_new.pressed.connect(_on_new_game)
	_btn_resume.pressed.connect(_on_resume)
	_btn_records.pressed.connect(_on_records)
	_btn_credits.pressed.connect(_on_credits)
	_btn_quit.pressed.connect(_on_quit)
	_btn_tutorial.pressed.connect(_on_toggle_tutorial)
	_btn_user_tracks.pressed.connect(_on_user_tracks)
	_btn_options.pressed.connect(_on_options)

	if OS.has_feature("web"):
		_btn_quit.visible = false
		_btn_quit.focus_mode = Control.FOCUS_NONE
	if OS.get_name() in ["Web", "Android", "iOS"]:
		_btn_user_tracks.visible = false
		_btn_user_tracks.focus_mode = Control.FOCUS_NONE
		_btn_tutorial.offset_top = -74.0
		_btn_tutorial.offset_bottom = -50.0
		_hint_label.visible = false

	I18n.language_changed.connect(func(_lang: String) -> void: _refresh_ui())
	_refresh_ui()
	_btn_new.grab_focus()

	AudioManager.play_music_key("menu_music", true, 0.0, 0.0)
	var music_player: AudioStreamPlayer = AudioManager.get_music_player()
	var m_tween: Tween = create_tween()
	m_tween.tween_method(func(v: float) -> void:
		AudioManager.set_music_base_volume(v)
	, 0.0, 0.5, 1.0)

	_start_pan_cycle()


func _refresh_ui() -> void:
	_title_label.text = I18n.t("game_title")
	_hint_label.text = I18n.t("fullscreen_hint")
	_version_label.text = I18n.t("version", {"version": GameConstants.VERSION})

	_btn_new.text = I18n.t("btn_new_game")
	_btn_credits.text = I18n.t("btn_credits")
	_btn_quit.text = I18n.t("btn_quit_game")
	_btn_tutorial.text = I18n.t("btn_tutorial")
	_btn_user_tracks.text = I18n.t("btn_user_tracks")
	_btn_options.text = I18n.t("btn_options")
	_btn_records.text = I18n.t("btn_records")

	if SaveManager.exists("workday_save"):
		var save_data: Dictionary = SaveManager.load_slot("workday_save", {})
		_btn_resume.disabled = false
		_btn_resume.focus_mode = Control.FOCUS_ALL
		_btn_resume.text = I18n.t("btn_resume_work_day", {"day": int(save_data.get("day", 1))})
	else:
		_btn_resume.disabled = true
		_btn_resume.focus_mode = Control.FOCUS_NONE
		_btn_resume.text = I18n.t("btn_resume_work")

	var has_any_record: bool = false
	if SaveManager.exists("records"):
		var rec: Dictionary = SaveManager.load_slot("records", {})
		has_any_record = not (rec.get("workday", []) as Array).is_empty() or not (rec.get("arcade", []) as Array).is_empty()

	_btn_records.visible = has_any_record
	if has_any_record:
		_btn_records.offset_left = -110.0
		_btn_records.offset_right = -10.0
		_btn_credits.offset_left = 10.0
		_btn_credits.offset_right = 110.0
	else:
		_btn_credits.offset_left = -50.0
		_btn_credits.offset_right = 50.0

	_btn_tutorial.theme_type_variation = &"ActiveButton" if GameFlow.tutorial_enabled else &""


func _start_pan_cycle() -> void:
	if _pan_tween != null and _pan_tween.is_valid():
		_pan_tween.kill()
	_scene_fade.color.a = 1.0
	var target: Vector2 = _pick_far_position()
	_pan_tween = create_tween()
	_pan_tween.tween_property(_scene_fade, "color:a", 0.0, 1.0)
	_pan_tween.tween_property(_camera, "global_position", target, 6.0)
	_pan_tween.tween_property(_scene_fade, "color:a", 1.0, 1.0)
	_pan_tween.tween_callback(func() -> void:
		_camera.global_position = _pick_far_position()
		_start_pan_cycle()
	)


func _pick_far_position() -> Vector2:
	if _positions.size() <= 1:
		return _positions[0]
	var far: Array[Vector2] = []
	for p in _positions:
		if p.distance_to(_camera.global_position) > 200.0:
			far.append(p)
	var pool: Array[Vector2] = far if not far.is_empty() else _positions
	return pool[randi() % pool.size()]


func _on_new_game() -> void:
	AudioManager.play_sfx("press")
	var modal: Control = (load("res://src/menus/mode_selection.tscn") as PackedScene).instantiate() as Control
	GameFlow.push_modal(modal, false)


func _on_resume() -> void:
	AudioManager.play_sfx("press")
	var save_data: Dictionary = SaveManager.load_slot("workday_save", {})
	AudioManager.stop_music()
	GameFlow.start_gameplay("workday", {
		"money": float(save_data.get("money", 0.0)),
		"day": int(save_data.get("day", 1)),
		"taxi_health": float(save_data.get("health", GameConstants.TAXI_MAX_HEALTH)),
		"is_loaded_run": true,
	})


func _on_records() -> void:
	AudioManager.play_sfx("press")
	GameFlow.change_scene("res://src/menus/records_screen.tscn", 0.6, 0.5)


func _on_credits() -> void:
	AudioManager.play_sfx("press")
	var mb: MessageBoxModal = (load("res://src/menus/message_box.tscn") as PackedScene).instantiate() as MessageBoxModal
	mb.setup(I18n.t("msg_credits_title"), I18n.t("msg_credits_text"))
	GameFlow.push_modal(mb, false)


func _on_quit() -> void:
	AudioManager.play_sfx("press")
	get_tree().quit()


func _on_toggle_tutorial() -> void:
	AudioManager.play_sfx("press")
	GameFlow.set_tutorial_enabled(not GameFlow.tutorial_enabled)
	_btn_tutorial.theme_type_variation = &"ActiveButton" if GameFlow.tutorial_enabled else &""


func _on_user_tracks() -> void:
	AudioManager.play_sfx("press")
	var mb: MessageBoxModal = (load("res://src/menus/message_box.tscn") as PackedScene).instantiate() as MessageBoxModal
	mb.setup(I18n.t("msg_user_tracks_title"), I18n.t("msg_user_tracks_info"))
	mb.closed.connect(_open_user_tracks_folder)
	GameFlow.push_modal(mb, false)


func _open_user_tracks_folder() -> void:
	if OS.get_name() in ["Web", "Android", "iOS"]:
		return
	var home: String = OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	if home.is_empty():
		return
	var base_path: String = home.path_join("Vibe Taxi User Tracks")
	for genre in ["rock", "pop", "jazz", "hiphop", "electronic"]:
		DirAccess.make_dir_recursive_absolute(base_path.path_join(genre))
	OS.shell_open(base_path)


func _on_options() -> void:
	AudioManager.play_sfx("press")
	var opts: OptionsMenuModal = (load("res://src/menus/options_menu.tscn") as PackedScene).instantiate() as OptionsMenuModal
	opts.closed.connect(_refresh_ui)
	GameFlow.push_modal(opts, false)
