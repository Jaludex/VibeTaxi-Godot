extends Node

## Central audio playback manager using Godot AudioServer buses and pooled SFX players.

const SFX_PATHS: Dictionary = {
	"crash_car": "res://assets/sounds/crash_sounds/crash_car.wav",
	"crash_mail": "res://assets/sounds/crash_sounds/crash_mail.wav",
	"crash_solid": "res://assets/sounds/crash_sounds/crash_solid.wav",
	"crash_wall": "res://assets/sounds/crash_sounds/crash_wall.wav",
	"engine_start": "res://assets/sounds/car_sounds/engine_start.wav",
	"drifting": "res://assets/sounds/car_sounds/drifting.wav",
	"idle_normal": "res://assets/sounds/car_sounds/idle-normal.wav",
	"idle_damaged": "res://assets/sounds/car_sounds/idle-damaged.wav",
	"engine1": "res://assets/sounds/car_sounds/engine1.wav",
	"engine2": "res://assets/sounds/car_sounds/engine2.wav",
	"into_vibe": "res://assets/sounds/misc/into_vibe.wav",
	"out_vibe": "res://assets/sounds/misc/out_vibe.wav",
	"win": "res://assets/sounds/misc/victory.wav",
	"honk": "res://assets/sounds/car_sounds/car_honk.wav",
	"money": "res://assets/sounds/misc/gain_money.wav",
	"fix": "res://assets/sounds/misc/fix.wav",
	"press": "res://assets/sounds/misc/press.wav",
	"game_over": "res://assets/sounds/misc/game_over.wav",
	"pause": "res://assets/sounds/misc/pause.wav",
	"unpause": "res://assets/sounds/misc/unpause.wav",
	"bleep1": "res://assets/sounds/text_blips/bleep001.wav",
	"bleep2": "res://assets/sounds/text_blips/bleep002.wav",
	"bleep3": "res://assets/sounds/text_blips/bleep003.wav",
	"bleep4": "res://assets/sounds/text_blips/bleep004.wav",
	"bleep5": "res://assets/sounds/text_blips/bleep005.wav",
	"bonus": "res://assets/sounds/misc/bonus.wav",
	"fatal": "res://assets/sounds/ranks/fatal.ogg",
	"bad": "res://assets/sounds/ranks/bad.wav",
	"good": "res://assets/sounds/ranks/good.ogg",
	"awesome": "res://assets/sounds/ranks/awesome.wav",
	"vibe": "res://assets/sounds/ranks/vibe.wav",
	"city_soundscape": "res://assets/music/city_soundscape.ogg",
	"menu_music": "res://assets/music/menu.ogg",
}

const WEB_PREWARM_INTERVAL_SEC: float = 0.15

var _sfx_cache: Dictionary = {}
var _music_cache: Dictionary = {}
var _prewarm_queue: Array[String] = []
var _prewarm_timer: float = 0.0
var _sfx_pool: Array[AudioStreamPlayer] = []
@onready var _music_player: AudioStreamPlayer = $MusicPlayer
@onready var _ambient_player: AudioStreamPlayer = $AmbientPlayer
@onready var _sfx_pool_root: Node = $SFXPool
var _base_music_volume: float = 0.5


func _ready() -> void:
	for child in _sfx_pool_root.get_children():
		if child is AudioStreamPlayer:
			_sfx_pool.append(child as AudioStreamPlayer)
	# Stream long OGG music/ambient tracks instead of Web's default Sample mode,
	# which synchronously decodes entire tracks into PCM buffers on first play().
	_music_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_ambient_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	set_process(false)
	if OS.has_feature("web"):
		queue_web_music_prewarm()


func _process(delta: float) -> void:
	if _prewarm_queue.is_empty():
		set_process(false)
		return
	# Only warm OGG streams outside active driving to avoid mid-gameplay WASM hitches.
	var scene: Node = get_tree().current_scene
	if scene is PlayScene and not get_tree().paused and not GameFlow.has_modals():
		return
	_prewarm_timer -= delta
	if _prewarm_timer <= 0.0:
		_prewarm_timer = WEB_PREWARM_INTERVAL_SEC
		var path: String = _prewarm_queue.pop_front() as String
		var stream: AudioStream = get_music_stream(path)
		if stream != null:
			stream.get_length()


func _exit_tree() -> void:
	stop_all_audio()
	_sfx_pool.clear()


func stop_all_audio() -> void:
	_prewarm_queue.clear()
	set_process(false)
	for player in _sfx_pool:
		player.stop()
		player.stream = null
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	if _ambient_player != null:
		_ambient_player.stop()
		_ambient_player.stream = null
	_sfx_cache.clear()
	_music_cache.clear()


func queue_web_music_prewarm() -> void:
	_prewarm_queue.clear()
	var files: PackedStringArray = ResourceLoader.list_directory("res://resources/radio")
	if files.is_empty():
		var dir: DirAccess = DirAccess.open("res://resources/radio")
		if dir != null:
			files = dir.get_files()
	files.sort()

	var station_lists: Array[Array] = []
	var max_len: int = 0
	for raw_name in files:
		var fname: String = raw_name.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		var station: RadioStationDef = load("res://resources/radio/" + fname) as RadioStationDef
		if station == null or station.track_paths.is_empty():
			continue
		var paths: Array = []
		for p in station.track_paths:
			if not p.is_empty() and not _music_cache.has(p):
				paths.append(p)
		if not paths.is_empty():
			paths.shuffle()
			station_lists.append(paths)
			max_len = maxi(max_len, paths.size())

	# Interleave round-robin across stations so every station has cached tracks early.
	for i in max_len:
		for paths in station_lists:
			if i < paths.size():
				_prewarm_queue.append(str(paths[i]))
	_prewarm_timer = WEB_PREWARM_INTERVAL_SEC
	set_process(not _prewarm_queue.is_empty())


func has_music_stream(path: String) -> bool:
	return _music_cache.has(path)


func is_music_prewarm_pending() -> bool:
	return not _prewarm_queue.is_empty()


func get_music_stream(path: String) -> AudioStream:
	if _music_cache.has(path):
		return _music_cache[path] as AudioStream
	var stream: AudioStream = null
	if path.begins_with("res://"):
		stream = load(path) as AudioStream
	else:
		match path.get_extension().to_lower():
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(path)
			"mp3":
				stream = AudioStreamMP3.load_from_file(path)
			"wav":
				stream = AudioStreamWAV.load_from_file(path)
	if stream != null:
		_music_cache[path] = stream
	return stream


func get_stream(key: String) -> AudioStream:
	if _sfx_cache.has(key):
		return _sfx_cache[key] as AudioStream
	if not SFX_PATHS.has(key):
		return null
	var path: String = str(SFX_PATHS[key])
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path) as AudioStream
	if stream != null:
		_sfx_cache[key] = stream
	return stream


func play_sfx(key: String, volume_scale: float = 1.0, bus_name: StringName = &"SFX") -> AudioStreamPlayer:
	var stream: AudioStream = get_stream(key)
	if stream == null or volume_scale <= 0.001:
		return null

	var chosen: AudioStreamPlayer = null
	for player in _sfx_pool:
		if not player.playing:
			chosen = player
			break
	if chosen == null:
		chosen = _sfx_pool[0]

	chosen.stop()
	chosen.stream = stream
	chosen.bus = bus_name
	chosen.volume_db = linear_to_db(clampf(volume_scale, 0.0001, 1.0))
	chosen.play()
	return chosen


func play_music_stream(stream: AudioStream, loop: bool = false, start_sec: float = 0.0, base_vol: float = -1.0) -> void:
	if stream == null:
		return
	if base_vol >= 0.0:
		set_music_base_volume(base_vol)
	_set_stream_loop(stream, loop)
	_music_player.stop()
	_music_player.stream = stream
	_music_player.stream_paused = false
	var safe_start: float = maxf(0.0, start_sec)
	var stream_len: float = stream.get_length()
	if stream_len > 1.0 and safe_start >= stream_len:
		safe_start = fmod(safe_start, stream_len * 0.8)
	_music_player.play(safe_start)


func play_music_key(key: String, loop: bool = true, start_sec: float = 0.0, base_vol: float = 0.5) -> void:
	var stream: AudioStream = get_stream(key)
	if stream != null:
		play_music_stream(stream, loop, start_sec, base_vol)


func stop_music() -> void:
	_music_player.stop()


func set_music_paused(paused: bool) -> void:
	_music_player.stream_paused = paused


func is_music_playing() -> bool:
	return _music_player.playing and not _music_player.stream_paused


func set_music_base_volume(base_vol: float) -> void:
	_base_music_volume = clampf(base_vol, 0.0, 1.0)
	_music_player.volume_db = -80.0 if _base_music_volume <= 0.001 else linear_to_db(_base_music_volume)


func get_music_player() -> AudioStreamPlayer:
	return _music_player


func start_ambient(key: String, base_vol: float = 0.5) -> void:
	var stream: AudioStream = get_stream(key)
	if stream == null:
		return
	_set_stream_loop(stream, true)
	_ambient_player.stream = stream
	_ambient_player.stream_paused = false
	set_ambient_base_volume(base_vol)
	_ambient_player.play()


func set_ambient_base_volume(base_vol: float) -> void:
	var clamped: float = clampf(base_vol, 0.0, 1.0)
	_ambient_player.volume_db = -80.0 if clamped <= 0.001 else linear_to_db(clamped)


func set_ambient_paused(paused: bool) -> void:
	_ambient_player.stream_paused = paused


func stop_ambient() -> void:
	_ambient_player.stop()


func stop_gameplay_audio() -> void:
	stop_music()
	stop_ambient()
	for player in _sfx_pool:
		if player.bus == &"Engine" or player.bus == &"Ambient":
			player.stop()


func play_preview(category: String) -> void:
	match category:
		"master", "sfx":
			play_sfx("bleep1", 1.0, &"SFX")
		"music":
			if not _music_player.playing:
				play_sfx("bleep3", 1.0, &"Music")
		"engine":
			play_sfx("bleep2", 1.0, &"Engine")
		"ambient":
			play_sfx("bleep4", 1.0, &"Ambient")


func _set_stream_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamOggVorbis:
		var ogg: AudioStreamOggVorbis = stream as AudioStreamOggVorbis
		if ogg.loop != loop:
			ogg.loop = loop
	elif stream is AudioStreamMP3:
		var mp3: AudioStreamMP3 = stream as AudioStreamMP3
		if mp3.loop != loop:
			mp3.loop = loop
	elif stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop and wav.loop_end <= 0:
			wav.loop_begin = 0
			wav.loop_end = maxi(1, int(round(wav.get_length() * float(wav.mix_rate))))
