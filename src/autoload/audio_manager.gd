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

var _sfx_cache: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
@onready var _music_player: AudioStreamPlayer = $MusicPlayer
@onready var _ambient_player: AudioStreamPlayer = $AmbientPlayer
@onready var _sfx_pool_root: Node = $SFXPool
var _base_music_volume: float = 0.5


func _ready() -> void:
	for child in _sfx_pool_root.get_children():
		if child is AudioStreamPlayer:
			_sfx_pool.append(child as AudioStreamPlayer)


func _exit_tree() -> void:
	for player in _sfx_pool:
		player.stop()
		player.stream = null
	_sfx_pool.clear()
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	if _ambient_player != null:
		_ambient_player.stop()
		_ambient_player.stream = null
	_sfx_cache.clear()


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
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	elif stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop and wav.loop_end <= 0:
			wav.loop_begin = 0
			wav.loop_end = maxi(1, int(round(wav.get_length() * float(wav.mix_rate))))
