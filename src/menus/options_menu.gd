class_name OptionsMenuModal
extends Control

## Tabbed Options modal: Audio (5 volume sliders) and Game (Fullscreen, Deadzone, FPS, Language, Debug).

signal closed

const FPS_CYCLE: Array[Variant] = [30, 60, 90, 120, 144, "auto", 0]

var _active_tab: String = "audio"
var _is_exiting: bool = false

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _title_label: Label = $Panel/TitleLabel
@onready var _btn_tab_audio: Button = $Panel/BtnTabAudio
@onready var _btn_tab_game: Button = $Panel/BtnTabGame
@onready var _audio_tab: Control = $Panel/AudioTab
@onready var _game_tab: Control = $Panel/GameTab
@onready var _btn_reset: Button = $Panel/BtnReset
@onready var _btn_back: Button = $Panel/BtnBack

# Audio Tab
@onready var _lbl_master: Label = $Panel/AudioTab/LblMaster
@onready var _sld_master: HSlider = $Panel/AudioTab/SldMaster
@onready var _val_master: Label = $Panel/AudioTab/ValMaster
@onready var _lbl_music: Label = $Panel/AudioTab/LblMusic
@onready var _sld_music: HSlider = $Panel/AudioTab/SldMusic
@onready var _val_music: Label = $Panel/AudioTab/ValMusic
@onready var _lbl_sfx: Label = $Panel/AudioTab/LblSfx
@onready var _sld_sfx: HSlider = $Panel/AudioTab/SldSfx
@onready var _val_sfx: Label = $Panel/AudioTab/ValSfx
@onready var _lbl_engine: Label = $Panel/AudioTab/LblEngine
@onready var _sld_engine: HSlider = $Panel/AudioTab/SldEngine
@onready var _val_engine: Label = $Panel/AudioTab/ValEngine
@onready var _lbl_ambient: Label = $Panel/AudioTab/LblAmbient
@onready var _sld_ambient: HSlider = $Panel/AudioTab/SldAmbient
@onready var _val_ambient: Label = $Panel/AudioTab/ValAmbient

# Game Tab
@onready var _chk_fullscreen: CheckBox = $Panel/GameTab/ChkFullscreen
@onready var _lbl_deadzone: Label = $Panel/GameTab/LblDeadzone
@onready var _sld_deadzone: HSlider = $Panel/GameTab/SldDeadzone
@onready var _val_deadzone: Label = $Panel/GameTab/ValDeadzone
@onready var _vis_deadzone: DeadzoneVisual = $Panel/GameTab/DeadzoneVisual
@onready var _chk_fps: CheckBox = $Panel/GameTab/ChkFps
@onready var _chk_debug: CheckBox = $Panel/GameTab/ChkDebug
@onready var _chk_focus: CheckBox = $Panel/GameTab/ChkFocus
@onready var _chk_discord: CheckBox = $Panel/GameTab/ChkDiscord
@onready var _btn_language: Button = $Panel/GameTab/BtnLanguage
@onready var _btn_fps: Button = $Panel/GameTab/BtnFps
@onready var _chk_touch_controls: CheckBox = $Panel/GameTab/ChkTouchControls
@onready var _btn_touch_mode: Button = $Panel/GameTab/BtnTouchMode


func _ready() -> void:
	_wire_signals()
	_refresh_labels()
	_sync_values_from_config()
	_set_tab("audio")
	if OS.has_feature("web"):
		_btn_fps.visible = false
		_btn_fps.focus_mode = Control.FOCUS_NONE
	if OS.get_name() in ["Android", "iOS"]:
		_chk_fullscreen.visible = false
		_chk_fullscreen.focus_mode = Control.FOCUS_NONE
	if OS.get_name() in ["Web", "Android", "iOS"]:
		_chk_discord.visible = false
		_chk_discord.focus_mode = Control.FOCUS_NONE
	_btn_tab_audio.grab_focus()

	_dim.color.a = 0.0
	_panel.position.y = -260.0
	var target_y: float = (get_viewport_rect().size.y - _panel.size.y) * 0.5
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 180.0 / 255.0, 0.3)
	tween.tween_property(_panel, "position:y", target_y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	var actual_fs: bool = ConfigManager.is_fullscreen()
	if _chk_fullscreen.button_pressed != actual_fs:
		_chk_fullscreen.set_pressed_no_signal(actual_fs)


func _unhandled_input(event: InputEvent) -> void:
	if GameFlow.get_top_modal() != self:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_on_back()
	elif event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event as InputEventJoypadButton
		if jb.pressed and (jb.button_index == JOY_BUTTON_LEFT_SHOULDER or jb.button_index == JOY_BUTTON_RIGHT_SHOULDER):
			get_viewport().set_input_as_handled()
			AudioManager.play_sfx("press")
			var target_tab: String = "game" if _active_tab == "audio" else "audio"
			_set_tab(target_tab)
			if target_tab == "audio":
				_btn_tab_audio.grab_focus()
			else:
				_btn_tab_game.grab_focus()


func _wire_signals() -> void:
	_btn_tab_audio.pressed.connect(func() -> void:
		AudioManager.play_sfx("press")
		_set_tab("audio")
	)
	_btn_tab_game.pressed.connect(func() -> void:
		AudioManager.play_sfx("press")
		_set_tab("game")
	)
	_btn_reset.pressed.connect(_on_reset)
	_btn_back.pressed.connect(_on_back)

	_sld_master.value_changed.connect(_on_vol_changed.bind("master_volume", "master", _val_master))
	_sld_music.value_changed.connect(_on_vol_changed.bind("music_volume", "music", _val_music))
	_sld_sfx.value_changed.connect(_on_vol_changed.bind("sfx_volume", "sfx", _val_sfx))
	_sld_engine.value_changed.connect(_on_vol_changed.bind("engine_volume", "engine", _val_engine))
	_sld_ambient.value_changed.connect(_on_vol_changed.bind("ambient_volume", "ambient", _val_ambient))

	_chk_fullscreen.toggled.connect(func(v: bool) -> void:
		AudioManager.play_sfx("press")
		ConfigManager.set_value("fullscreen", v)
	)
	_sld_deadzone.value_changed.connect(func(v: float) -> void:
		ConfigManager.set_value("gamepad_deadzone", v)
		_vis_deadzone.deadzone = v
		_val_deadzone.text = "%d%%" % int(round(v * 100.0))
	)
	_chk_fps.toggled.connect(func(v: bool) -> void: ConfigManager.set_value("show_fps", v))
	_chk_debug.toggled.connect(func(v: bool) -> void: ConfigManager.set_value("physics_debug", v))
	_chk_focus.toggled.connect(func(v: bool) -> void: ConfigManager.set_value("pause_on_focus_loss", v))
	_chk_discord.toggled.connect(func(v: bool) -> void: ConfigManager.set_value("discord_rpc", v))
	_btn_language.pressed.connect(_on_language_pressed)
	_btn_fps.pressed.connect(_on_fps_pressed)
	_chk_touch_controls.toggled.connect(func(v: bool) -> void:
		AudioManager.play_sfx("press")
		ConfigManager.set_value("touch_controls", v, true)
		_btn_touch_mode.disabled = not v
	)
	_btn_touch_mode.pressed.connect(_on_touch_mode_pressed)


func _on_vol_changed(val: float, key: String, cat: String, lbl: Label) -> void:
	ConfigManager.set_value(key, val)
	lbl.text = "%d%%" % int(round(val * 100.0))
	AudioManager.play_preview(cat)


func _set_tab(tab: String) -> void:
	_active_tab = tab
	_audio_tab.visible = (tab == "audio")
	_game_tab.visible = (tab == "game")
	_btn_tab_audio.theme_type_variation = &"ActiveButton" if tab == "audio" else &""
	_btn_tab_game.theme_type_variation = &"ActiveButton" if tab == "game" else &""


func _refresh_labels() -> void:
	_title_label.text = I18n.t("options_title")
	_btn_tab_audio.text = I18n.t("tab_audio")
	_btn_tab_game.text = I18n.t("tab_game")
	_btn_reset.text = I18n.t("btn_reset_defaults")
	_btn_back.text = I18n.t("btn_back")

	_lbl_master.text = I18n.t("opt_master")
	_lbl_music.text = I18n.t("opt_music")
	_lbl_sfx.text = I18n.t("opt_sfx")
	_lbl_engine.text = I18n.t("opt_engine")
	_lbl_ambient.text = I18n.t("opt_ambient")

	_chk_fullscreen.text = I18n.t("opt_fullscreen")
	_lbl_deadzone.text = I18n.t("opt_deadzone")
	_chk_fps.text = I18n.t("opt_show_fps")
	_chk_debug.text = I18n.t("opt_debug_visuals")
	_chk_focus.text = I18n.t("opt_pause_on_focus_loss")
	_chk_discord.text = I18n.t("opt_discord_rpc")

	var lang_name: String = I18n.t("language_name")
	_btn_language.text = "%s: %s" % [I18n.t("btn_language"), lang_name]
	_btn_fps.text = _get_fps_button_text()
	_chk_touch_controls.text = I18n.t("opt_touch_controls")
	_btn_touch_mode.text = _get_touch_mode_button_text()


func _sync_values_from_config() -> void:
	_sld_master.set_value_no_signal(float(ConfigManager.get_value("master_volume", 1.0)))
	_sld_music.set_value_no_signal(float(ConfigManager.get_value("music_volume", 0.8)))
	_sld_sfx.set_value_no_signal(float(ConfigManager.get_value("sfx_volume", 1.0)))
	_sld_engine.set_value_no_signal(float(ConfigManager.get_value("engine_volume", 1.0)))
	_sld_ambient.set_value_no_signal(float(ConfigManager.get_value("ambient_volume", 1.0)))

	_val_master.text = "%d%%" % int(round(_sld_master.value * 100.0))
	_val_music.text = "%d%%" % int(round(_sld_music.value * 100.0))
	_val_sfx.text = "%d%%" % int(round(_sld_sfx.value * 100.0))
	_val_engine.text = "%d%%" % int(round(_sld_engine.value * 100.0))
	_val_ambient.text = "%d%%" % int(round(_sld_ambient.value * 100.0))

	var dz: float = float(ConfigManager.get_value("gamepad_deadzone", 0.25))
	_sld_deadzone.set_value_no_signal(dz)
	_vis_deadzone.deadzone = dz
	_val_deadzone.text = "%d%%" % int(round(dz * 100.0))

	_chk_fullscreen.set_pressed_no_signal(ConfigManager.is_fullscreen())
	_chk_fps.set_pressed_no_signal(bool(ConfigManager.get_value("show_fps", false)))
	_chk_debug.set_pressed_no_signal(bool(ConfigManager.get_value("physics_debug", false)))
	_chk_focus.set_pressed_no_signal(bool(ConfigManager.get_value("pause_on_focus_loss", true)))
	_chk_discord.set_pressed_no_signal(bool(ConfigManager.get_value("discord_rpc", true)))
	var touch_on: bool = ConfigManager.is_touch_controls_enabled()
	_chk_touch_controls.set_pressed_no_signal(touch_on)
	_btn_touch_mode.disabled = not touch_on
	_btn_touch_mode.text = _get_touch_mode_button_text()
	_btn_fps.text = _get_fps_button_text()


func _get_touch_mode_button_text() -> String:
	var mode: String = str(ConfigManager.get_value("touch_mode", "joystick"))
	var mode_label: String = I18n.t("touch_mode_drag" if mode == "drag" else "touch_mode_joystick")
	return I18n.t("opt_touch_mode", {"mode": mode_label})


func _on_touch_mode_pressed() -> void:
	AudioManager.play_sfx("press")
	var cur: String = str(ConfigManager.get_value("touch_mode", "joystick"))
	var next_mode: String = "drag" if cur == "joystick" else "joystick"
	ConfigManager.set_value("touch_mode", next_mode, true)
	_btn_touch_mode.text = _get_touch_mode_button_text()


func _get_fps_button_text() -> String:
	var val: Variant = ConfigManager.get_value("fps_limit", 60)
	var label_str: String = ""
	if val is String and val == "auto":
		label_str = I18n.t("fps_auto")
	elif int(val) == 0:
		label_str = I18n.t("fps_uncapped")
	else:
		label_str = str(int(val))
	return "%s: %s" % [I18n.t("opt_fps_limit"), label_str]


func _on_fps_pressed() -> void:
	AudioManager.play_sfx("press")
	var cur: Variant = ConfigManager.get_value("fps_limit", 60)
	var idx: int = FPS_CYCLE.find(cur)
	if idx < 0:
		idx = 1
	var next_val: Variant = FPS_CYCLE[(idx + 1) % FPS_CYCLE.size()]
	ConfigManager.set_value("fps_limit", next_val, true)
	_btn_fps.text = _get_fps_button_text()


func _on_language_pressed() -> void:
	AudioManager.play_sfx("press")
	var lang_modal: LanguageSelectionModal = (load("res://src/menus/language_selection.tscn") as PackedScene).instantiate() as LanguageSelectionModal
	lang_modal.standalone_mode = false
	lang_modal.closed.connect(_refresh_labels)
	GameFlow.push_modal(lang_modal, get_tree().paused)


func _on_reset() -> void:
	AudioManager.play_sfx("press")
	ConfigManager.reset_defaults()
	_sync_values_from_config()
	_refresh_labels()


func _on_back() -> void:
	if _is_exiting:
		return
	_is_exiting = true
	AudioManager.play_sfx("press")
	ConfigManager.save_config()

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.0, 0.3)
	tween.tween_property(_panel, "position:y", -260.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		GameFlow.pop_modal(self)
		closed.emit()
	)
