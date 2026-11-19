extends Node

## Persistent configuration manager synchronizing AudioServer, DisplayServer, and Engine settings.

signal config_changed(key: String, value: Variant)

const CONFIG_SLOT: String = "config"

const DEFAULTS: Dictionary = {
	"language": "",
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	"engine_volume": 1.0,
	"ambient_volume": 1.0,
	"fullscreen": false,
	"gamepad_deadzone": 0.25,
	"show_fps": false,
	"physics_debug": false,
	"pause_on_focus_loss": true,
	"discord_rpc": true,
	"fps_limit": 60,
	"touch_mode": "joystick",
	"touch_controls": false,
}

var _data: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	load_config()


func load_config() -> Dictionary:
	_data = DEFAULTS.duplicate(true)
	if _is_touch_platform_default():
		_data["touch_controls"] = true
	if SaveManager.exists(CONFIG_SLOT):
		var saved: Dictionary = SaveManager.load_slot(CONFIG_SLOT, {})
		for key in saved.keys():
			_data[key] = saved[key]
	_loaded = true
	apply_all()
	return _data


static func _is_touch_platform_default() -> bool:
	return OS.get_name() in ["Android", "iOS"] or DisplayServer.is_touchscreen_available()


func is_touch_controls_enabled() -> bool:
	return bool(get_value("touch_controls", _is_touch_platform_default()))


func get_value(key: String, fallback: Variant = null) -> Variant:
	if not _loaded:
		load_config()
	if _data.has(key):
		return _data[key]
	if fallback != null:
		return fallback
	return DEFAULTS.get(key)


func set_value(key: String, value: Variant, auto_save: bool = false) -> void:
	if not _loaded:
		load_config()
	_data[key] = value
	_apply_key(key, value)
	config_changed.emit(key, value)
	if auto_save:
		save_config()


func save_config() -> void:
	if not _loaded:
		load_config()
	SaveManager.save_slot(CONFIG_SLOT, _data)


func reset_defaults() -> void:
	var current_lang: String = str(get_value("language", "es"))
	if current_lang.is_empty():
		current_lang = "es"
	_data = DEFAULTS.duplicate(true)
	_data["touch_controls"] = _is_touch_platform_default()
	_data["language"] = current_lang
	apply_all()
	save_config()
	for key in _data.keys():
		config_changed.emit(str(key), _data[key])


func has_language_selected() -> bool:
	return not str(get_value("language", "")).is_empty()


func apply_all() -> void:
	_apply_bus_volume("Master", float(get_value("master_volume", 1.0)))
	_apply_bus_volume("Music", float(get_value("music_volume", 0.8)))
	_apply_bus_volume("SFX", float(get_value("sfx_volume", 1.0)))
	_apply_bus_volume("Engine", float(get_value("engine_volume", 1.0)))
	_apply_bus_volume("Ambient", float(get_value("ambient_volume", 1.0)))
	_apply_fullscreen(bool(get_value("fullscreen", false)))
	_apply_fps_limit(get_value("fps_limit", 60))
	_apply_deadzone(float(get_value("gamepad_deadzone", 0.25)))


func _apply_key(key: String, value: Variant) -> void:
	match key:
		"master_volume":
			_apply_bus_volume("Master", float(value))
		"music_volume":
			_apply_bus_volume("Music", float(value))
		"sfx_volume":
			_apply_bus_volume("SFX", float(value))
		"engine_volume":
			_apply_bus_volume("Engine", float(value))
		"ambient_volume":
			_apply_bus_volume("Ambient", float(value))
		"fullscreen":
			_apply_fullscreen(bool(value))
		"fps_limit":
			_apply_fps_limit(value)
		"gamepad_deadzone":
			_apply_deadzone(float(value))


func _apply_bus_volume(bus_name: String, linear_vol: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	var clamped: float = clampf(linear_vol, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_idx, clamped <= 0.001)
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(clamped, 0.0001)))


func _apply_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target_mode: DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)


func toggle_fullscreen() -> bool:
	var next_state: bool = not is_fullscreen()
	set_value("fullscreen", next_state, true)
	return next_state


func is_fullscreen() -> bool:
	if DisplayServer.get_name() == "headless":
		return bool(get_value("fullscreen", false))
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func get_effective_fps() -> int:
	if OS.has_feature("web"):
		return 0
	var val: Variant = get_value("fps_limit", 60)
	if val is String and val == "auto":
		var hz: float = DisplayServer.screen_get_refresh_rate()
		return int(round(hz)) if hz > 0.0 else 60
	return maxi(0, int(val))


func _apply_fps_limit(_val: Variant) -> void:
	Engine.max_fps = get_effective_fps()


func _apply_deadzone(dz: float) -> void:
	var clamped: float = clampf(dz, 0.05, 0.5)
	for action in ["steer_left", "steer_right", "steer_up", "steer_down"]:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, clamped)
