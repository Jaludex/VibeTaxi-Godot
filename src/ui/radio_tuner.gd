class_name RadioTuner
extends Control

## In-game radio UI with 6 stations, lazy desktop user tracks, dial animation, and auto-fade.

signal station_changed(genre: String, station_name: String)

const TUNE_DEBOUNCE_SEC: float = 0.22

@export var station_defs: Array[RadioStationDef] = []

var stations: Array[Dictionary] = []
var current_index: int = 0
var radio_volume: int = 50
var _user_tracks_loaded: Dictionary = {}
var _pending_tune_delay: float = 0.0

@onready var _marker: TextureRect = $Marker
@onready var _knob: TextureRect = $Knob
@onready var _btn_plus: Sprite2D = $BtnPlus
@onready var _btn_less: Sprite2D = $BtnLess
@onready var _station_label: Label = $StationLabel
@onready var _fade_timer: Timer = $FadeTimer

var _fade_tween: Tween
var _dial_tween: Tween


func _ready() -> void:
	modulate.a = 0.0
	_build_base_stations()

	_fade_timer.wait_time = GameConstants.RADIO_FADEOUT_TIME
	_fade_timer.timeout.connect(_start_fade_out)

	if _station_label != null:
		_station_label.text = get_current_station_name()

	_update_dial_immediate()
	AudioManager.set_music_base_volume(radio_volume / 100.0)


func _build_base_stations() -> void:
	stations.clear()
	if station_defs.is_empty():
		var files: PackedStringArray = ResourceLoader.list_directory("res://resources/radio")
		if files.is_empty():
			var dir: DirAccess = DirAccess.open("res://resources/radio")
			if dir != null:
				files = dir.get_files()
		files.sort()
		for raw_name in files:
			var fname: String = raw_name.trim_suffix(".remap")
			if fname.ends_with(".tres"):
				var loaded: RadioStationDef = load("res://resources/radio/" + fname) as RadioStationDef
				if loaded != null and not (loaded in station_defs):
					station_defs.append(loaded)

	for res in station_defs:
		if res == null:
			continue
		var tracks: Array = []
		for path_str in res.track_paths:
			if not path_str.is_empty():
				tracks.append(path_str)
		for stream in res.tracks:
			if stream != null:
				tracks.append(stream)
		stations.append({
			"name": res.station_name,
			"genre": res.genre,
			"vibe_color": res.vibe_color,
			"songs": tracks,
		})


func get_playable_genres() -> Array[String]:
	var genres: Array[String] = []
	for st in stations:
		var g: String = str(st.get("genre", ""))
		if not g.is_empty() and g != "off":
			genres.append(g)
	return genres


func get_station_vibe_color(genre: String) -> Color:
	for st in stations:
		if str(st.get("genre", "")) == genre:
			return st.get("vibe_color", Color.CYAN) as Color
	return Color.CYAN


func _process(delta: float) -> void:
	if _pending_tune_delay > 0.0:
		_pending_tune_delay -= delta
		if _pending_tune_delay <= 0.0:
			var tuned_songs: Array = stations[current_index]["songs"] as Array
			if not tuned_songs.is_empty():
				_play_random_track(tuned_songs, randf_range(0.0, 60.0))
		return

	var station: Dictionary = stations[current_index]
	var songs: Array = station["songs"] as Array
	if not songs.is_empty() and not AudioManager.get_music_player().playing:
		_play_random_track(songs, 0.0)


func _input(event: InputEvent) -> void:
	if not is_interactive() or get_tree().paused or GameFlow.has_modals():
		return
	var pos: Vector2 = Vector2.ZERO
	var triggered: bool = false
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			pos = st.position
			triggered = true
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.device != -1:
			pos = mb.position
			triggered = true
	if triggered and handle_pointer_at(pos):
		get_viewport().set_input_as_handled()


func is_interactive() -> bool:
	return visible and modulate.a > 0.15


func toggle_panel() -> void:
	AudioManager.play_sfx("press")
	if is_interactive():
		_fade_timer.stop()
		_start_fade_out()
	else:
		_trigger_activity()


func handle_pointer_at(global_pos: Vector2) -> bool:
	if not is_interactive():
		return false
	var local_pos: Vector2 = get_global_transform().affine_inverse() * global_pos
	if not Rect2(Vector2.ZERO, size).has_point(local_pos):
		return false
	if local_pos.x >= 416.0:
		if local_pos.y < 32.0:
			volume_up()
		else:
			volume_down()
	elif local_pos.x <= 68.0 or local_pos.x >= 245.0:
		next_station()
	else:
		prev_station()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_station"):
		next_station()
	elif event.is_action_pressed("prev_station"):
		prev_station()
	elif event.is_action_pressed("vol_up"):
		volume_up()
	elif event.is_action_pressed("vol_down"):
		volume_down()


func get_current_genre() -> String:
	return str(stations[current_index]["genre"])


func get_current_station_name() -> String:
	return str(stations[current_index]["name"])


func next_station() -> void:
	AudioManager.play_sfx("press")
	_trigger_activity()
	current_index = (current_index + 1) % stations.size()
	_apply_station_change()


func prev_station() -> void:
	AudioManager.play_sfx("press")
	_trigger_activity()
	current_index = (current_index - 1 + stations.size()) % stations.size()
	_apply_station_change()


func volume_up() -> void:
	AudioManager.play_sfx("press")
	_trigger_activity()
	radio_volume = mini(100, radio_volume + 10)
	AudioManager.set_music_base_volume(radio_volume / 100.0)
	_flash_button(_btn_plus)


func volume_down() -> void:
	AudioManager.play_sfx("press")
	_trigger_activity()
	radio_volume = maxi(0, radio_volume - 10)
	AudioManager.set_music_base_volume(radio_volume / 100.0)
	_flash_button(_btn_less)


func _flash_button(spr: Sprite2D) -> void:
	if spr == null:
		return
	spr.frame = 1
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		if is_instance_valid(spr):
			spr.frame = 0
	)


func _apply_station_change() -> void:
	var target_x: float = _get_marker_x(current_index)
	var target_deg: float = _get_knob_degrees(current_index)

	if _dial_tween != null and _dial_tween.is_valid():
		_dial_tween.kill()
	_dial_tween = create_tween().set_parallel(true)
	_dial_tween.tween_property(_marker, "position:x", target_x, 0.15)
	_dial_tween.tween_property(_knob, "rotation_degrees", target_deg, 0.15)

	if _station_label != null:
		_station_label.text = get_current_station_name()

	AudioManager.stop_music()
	var station: Dictionary = stations[current_index]
	var genre: String = str(station["genre"])
	_lazy_load_user_tracks(genre, station["songs"] as Array)

	var songs: Array = station["songs"] as Array
	# Debounce track load/play so rapid station zapping skips intermediate OGG decodes.
	_pending_tune_delay = TUNE_DEBOUNCE_SEC if not songs.is_empty() else 0.0

	station_changed.emit(genre, get_current_station_name())


func _play_random_track(songs: Array, start_sec: float) -> void:
	var pool: Array = songs
	if OS.has_feature("web") and AudioManager.is_music_prewarm_pending():
		var cached: Array = []
		for s in songs:
			if s is AudioStream or AudioManager.has_music_stream(str(s)):
				cached.append(s)
		if not cached.is_empty():
			pool = cached
	var entry: Variant = pool[randi() % pool.size()]
	var stream: AudioStream = entry as AudioStream if entry is AudioStream else AudioManager.get_music_stream(str(entry))
	if stream != null:
		AudioManager.play_music_stream(stream, false, start_sec, radio_volume / 100.0)


func _lazy_load_user_tracks(genre: String, target_songs: Array) -> void:
	if genre == "off" or _user_tracks_loaded.has(genre):
		return
	_user_tracks_loaded[genre] = true

	var os_name: String = OS.get_name()
	if os_name in ["Web", "Android", "iOS"]:
		return

	var home: String = OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	if home.is_empty():
		return

	var dir_path: String = home.path_join("Vibe Taxi User Tracks").path_join(genre)
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
		return

	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir():
			var ext: String = fname.get_extension().to_lower()
			if ext in ["mp3", "ogg", "wav"]:
				var full_path: String = dir_path.path_join(fname)
				if AudioManager.get_music_stream(full_path) != null:
					target_songs.append(full_path)
		fname = dir.get_next()
	dir.list_dir_end()


func _get_marker_x(idx: int) -> float:
	if stations.size() <= 1:
		return 80.0
	return 80.0 + (float(idx) / float(stations.size() - 1)) * 302.0


func _get_knob_degrees(idx: int) -> float:
	if stations.size() <= 1:
		return -90.0
	return -90.0 + (float(idx) / float(stations.size() - 1)) * 180.0


func _update_dial_immediate() -> void:
	if _marker != null:
		_marker.position = Vector2(_get_marker_x(current_index), 24.0)
	if _knob != null:
		_knob.rotation_degrees = _get_knob_degrees(current_index)


func _trigger_activity() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	modulate.a = 1.0
	_fade_timer.start()


func _start_fade_out() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, 1.0)
