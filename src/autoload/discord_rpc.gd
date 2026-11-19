extends Node

## Asynchronous Discord Rich Presence (IPC) client for desktop platforms (Linux, Windows, macOS).
## Uses StreamPeerUDS on Unix/macOS and named pipes on Windows inside a background Thread.

const CLIENT_ID: String = "1558733170730344582"
const BUTTON_LABEL: String = "View on itch.io"
const BUTTON_URL: String = "https://jaludex.itch.io/vibe-taxi"

const MIN_UPDATE_INTERVAL_SEC: float = 3.5
const RECONNECT_BACKOFF_SEC: float = 15.0
const POLL_INTERVAL_SEC: float = 0.25

const OP_HANDSHAKE: int = 0
const OP_FRAME: int = 1
const OP_CLOSE: int = 2

var _mutex: Mutex = Mutex.new()
var _thread: Thread = null
var _running: bool = false
var _enabled: bool = true

var _session_start: int = 0
var _pid: int = 0
var _nonce_counter: int = 0
var _sample_timer: float = 0.0

var _pending_presence: Dictionary = {}
var _last_sent_presence: Dictionary = {}
var _last_sent_time: float = 0.0
var _next_connect_attempt: float = 0.0

var _uds: StreamPeerUDS = null
var _pipe: FileAccess = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_start = int(Time.get_unix_time_from_system())
	_pid = OS.get_process_id()
	_enabled = bool(ConfigManager.get_value("discord_rpc", true))
	ConfigManager.config_changed.connect(_on_config_changed)

	if is_supported_platform() and DisplayServer.get_name() != "headless":
		_running = true
		_thread = Thread.new()
		_thread.start(_worker_loop)


func _exit_tree() -> void:
	_mutex.lock()
	_running = false
	_mutex.unlock()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _process(delta: float) -> void:
	if not _running:
		return
	_sample_timer += delta
	if _sample_timer < POLL_INTERVAL_SEC:
		return
	_sample_timer = 0.0

	_mutex.lock()
	var is_on: bool = _enabled
	_mutex.unlock()
	if not is_on:
		return

	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var presence: Dictionary = resolve_presence(tree.current_scene, GameFlow.get_modal_stack())
	_mutex.lock()
	if presence != _pending_presence:
		_pending_presence = presence
	_mutex.unlock()


func _on_config_changed(key: String, value: Variant) -> void:
	if key == "discord_rpc":
		set_enabled(bool(value))


func set_enabled(enabled: bool) -> void:
	_mutex.lock()
	_enabled = enabled
	if enabled:
		_next_connect_attempt = 0.0
	_mutex.unlock()


func is_connected_to_discord() -> bool:
	_mutex.lock()
	var connected: bool = _is_ipc_connected()
	_mutex.unlock()
	return connected


static func is_supported_platform() -> bool:
	return not OS.has_feature("web") and not (OS.get_name() in ["Web", "Android", "iOS"])


static func encode_frame(opcode: int, data: Dictionary) -> PackedByteArray:
	var payload: PackedByteArray = JSON.stringify(data).to_utf8_buffer()
	var header: PackedByteArray = PackedByteArray()
	header.resize(8)
	header.encode_u32(0, opcode)
	header.encode_u32(4, payload.size())
	return header + payload


static func build_activity_payload(presence: Dictionary, session_start: int, pid: int, nonce: String) -> Dictionary:
	var assets: Dictionary = {
		"large_image": str(presence.get("large_image", "logo")),
		"large_text": str(presence.get("large_text", "VibeTaxi")),
	}
	var small_image: String = str(presence.get("small_image", ""))
	if not small_image.is_empty():
		assets["small_image"] = small_image
		var small_text: String = str(presence.get("small_text", ""))
		if not small_text.is_empty():
			assets["small_text"] = small_text

	var activity: Dictionary = {
		"details": str(presence.get("details", "VibeTaxi")),
		"state": str(presence.get("state", "Driving around")),
		"timestamps": {"start": session_start},
		"assets": assets,
		"buttons": [
			{
				"label": BUTTON_LABEL,
				"url": BUTTON_URL,
			}
		],
	}
	return {
		"cmd": "SET_ACTIVITY",
		"args": {
			"pid": pid,
			"activity": activity,
		},
		"nonce": nonce,
	}


static func resolve_presence(current_scene: Node, modal_stack: Array[Control]) -> Dictionary:
	for i in range(modal_stack.size() - 1, -1, -1):
		var modal: Control = modal_stack[i]
		if not is_instance_valid(modal):
			continue
		if modal is MessageBoxModal or modal is ConfirmationBoxModal:
			continue
		if modal is PauseMenuModal:
			return {"details": "Paused", "state": "Taking a break"}
		if modal is OptionsMenuModal or modal is LanguageSelectionModal:
			return {"details": "Settings", "state": "Tuning options"}
		if modal is ModeSelectionModal:
			return {"details": "Mode Selection", "state": "Choosing a game mode"}
		if modal is EndOfDayModal:
			var eod_day: int = int(modal.get("_day"))
			var eod_money: float = float(modal.get("_money"))
			return {"details": "End of Day %d" % eod_day, "state": "Earnings: $%.0f" % eod_money}
		if modal is GameOverModal:
			return {"details": "Game Over", "state": "Shift ended"}
		if modal is NewRecordModal:
			return {"details": "New High Score!", "state": "Registering name in Hall of Fame"}

	if current_scene != null and is_instance_valid(current_scene):
		if current_scene is PlayScene:
			var ps: PlayScene = current_scene as PlayScene
			var strat: RuleStrategy = ps.rule_strategy
			if strat is TutorialStrategy:
				return {"details": "Tutorial", "state": "Learning the ropes"}
			if strat is WorkdayStrategy:
				var ws: WorkdayStrategy = strat as WorkdayStrategy
				var state_text: String = (
					"Carrying Passenger | $%.0f earned" % ws.money
					if ps.active_passenger != null
					else "Cruising | $%.0f / Goal $%.0f" % [ws.money, ws.fee]
				)
				return {
					"details": "Workday - Day %d" % ws.day,
					"state": state_text,
					"small_image": "workday",
					"small_text": "Day %d" % ws.day,
				}
			if strat is ArcadeStrategy:
				var arc: ArcadeStrategy = strat as ArcadeStrategy
				return {
					"details": "Arcade Mode",
					"state": "Score: %d | Passengers: %d" % [arc.score, arc.passengers_delivered],
					"small_image": "arcade",
					"small_text": "Arcade",
				}
			if strat is ZenStrategy:
				return {
					"details": "Zen Mode",
					"state": "Cruising the city (No limits)",
					"small_image": "zen",
					"small_text": "Zen Mode",
				}

		var scene_file: String = current_scene.scene_file_path.get_file()
		match scene_file:
			"opening.tscn":
				return {"details": "Starting up", "state": "Watching intro"}
			"title_screen.tscn":
				return {"details": "Main Menu", "state": "Selecting destination"}
			"records_screen.tscn":
				return {"details": "Hall of Fame", "state": "Checking top scores"}
			"language_selection.tscn":
				return {"details": "Settings", "state": "Tuning options"}

	return {"details": "VibeTaxi", "state": "Driving around"}


func _worker_loop() -> void:
	while true:
		_mutex.lock()
		var keep_running: bool = _running
		var is_enabled: bool = _enabled
		var pending: Dictionary = _pending_presence.duplicate()
		var next_attempt: float = _next_connect_attempt
		_mutex.unlock()

		if not keep_running:
			break

		var now: float = Time.get_unix_time_from_system()

		if not is_enabled:
			if _is_ipc_connected():
				_disconnect_ipc(true)
			_last_sent_presence = {}
			OS.delay_msec(200)
			continue

		if not _is_ipc_connected():
			if now >= next_attempt:
				_try_connect()
			OS.delay_msec(200)
			continue

		_poll_ipc()

		if _is_ipc_connected() and not pending.is_empty():
			if pending != _last_sent_presence and (now - _last_sent_time) >= MIN_UPDATE_INTERVAL_SEC:
				_send_activity(pending)

		OS.delay_msec(150)

	if _is_ipc_connected():
		_disconnect_ipc(true)


func _is_ipc_connected() -> bool:
	return _uds != null or _pipe != null


func _try_connect() -> void:
	var ok: bool = _try_connect_windows() if OS.get_name() == "Windows" else _try_connect_unix()
	if ok:
		_last_sent_time = 0.0
		_last_sent_presence = {}
	else:
		_mutex.lock()
		_next_connect_attempt = Time.get_unix_time_from_system() + RECONNECT_BACKOFF_SEC
		_mutex.unlock()


func _try_connect_unix() -> bool:
	var paths: Array[String] = _get_unix_socket_candidates()
	for sock_path in paths:
		var uds: StreamPeerUDS = StreamPeerUDS.new()
		if uds.connect_to_host(sock_path) != OK:
			continue
		for _i in 20:
			uds.poll()
			var st: StreamPeerSocket.Status = uds.get_status()
			if st == StreamPeerSocket.STATUS_CONNECTED:
				break
			if st == StreamPeerSocket.STATUS_ERROR:
				break
			OS.delay_msec(10)
		if uds.get_status() != StreamPeerSocket.STATUS_CONNECTED:
			uds.disconnect_from_host()
			continue
		if uds.put_data(encode_frame(OP_HANDSHAKE, {"v": 1, "client_id": CLIENT_ID})) != OK:
			uds.disconnect_from_host()
			continue
		var reply: Dictionary = _read_uds_frame(uds, 25)
		if str(reply.get("cmd", "")) == "DISPATCH":
			_uds = uds
			return true
		uds.disconnect_from_host()
	return false


func _get_unix_socket_candidates() -> Array[String]:
	var dirs: Array[String] = []
	var xdg: String = OS.get_environment("XDG_RUNTIME_DIR").rstrip("/")
	if not xdg.is_empty():
		dirs.append(xdg)
		dirs.append(xdg + "/app/com.discordapp.Discord")
		dirs.append(xdg + "/snap.discord")
	for env_key in ["TMPDIR", "TMP", "TEMP"]:
		var val: String = OS.get_environment(env_key).rstrip("/")
		if not val.is_empty() and not (val in dirs):
			dirs.append(val)
	if not ("/tmp" in dirs):
		dirs.append("/tmp")

	var candidates: Array[String] = []
	for dir_path in dirs:
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			continue
		var files: PackedStringArray = dir.get_files()
		for i in 10:
			var name_str: String = "discord-ipc-%d" % i
			if name_str in files:
				candidates.append(dir_path + "/" + name_str)
	return candidates


func _try_connect_windows() -> bool:
	for i in 10:
		var pipe_path: String = "\\\\.\\pipe\\discord-ipc-%d" % i
		var pipe: FileAccess = FileAccess.open(pipe_path, FileAccess.READ_WRITE)
		if pipe == null:
			continue
		pipe.store_buffer(encode_frame(OP_HANDSHAKE, {"v": 1, "client_id": CLIENT_ID}))
		pipe.flush()
		if pipe.get_error() != OK:
			pipe.close()
			continue
		var reply: Dictionary = _read_pipe_frame(pipe)
		if str(reply.get("cmd", "")) == "DISPATCH":
			_pipe = pipe
			return true
		pipe.close()
	return false


func _poll_ipc() -> void:
	if _uds != null:
		_uds.poll()
		if _uds.get_status() != StreamPeerSocket.STATUS_CONNECTED:
			_disconnect_ipc(false)
			return
		while _uds.get_available_bytes() >= 8:
			var frame: Dictionary = _read_uds_frame(_uds, 0)
			if frame.is_empty():
				break


func _send_activity(presence: Dictionary) -> void:
	_nonce_counter += 1
	var payload: Dictionary = build_activity_payload(presence, _session_start, _pid, str(_nonce_counter))
	if _send_ipc_frame(OP_FRAME, payload):
		_last_sent_presence = presence
		_last_sent_time = Time.get_unix_time_from_system()


func _send_ipc_frame(opcode: int, data: Dictionary) -> bool:
	var bytes: PackedByteArray = encode_frame(opcode, data)
	if _uds != null:
		if _uds.put_data(bytes) != OK:
			_disconnect_ipc(false)
			return false
		return true
	if _pipe != null:
		_pipe.store_buffer(bytes)
		_pipe.flush()
		if _pipe.get_error() != OK:
			_disconnect_ipc(false)
			return false
		if opcode == OP_FRAME:
			var reply: Dictionary = _read_pipe_frame(_pipe)
			if reply.is_empty():
				_disconnect_ipc(false)
				return false
		return true
	return false


func _disconnect_ipc(send_clear: bool) -> void:
	if send_clear and _is_ipc_connected():
		_nonce_counter += 1
		var clear_payload: Dictionary = {
			"cmd": "SET_ACTIVITY",
			"args": {"pid": _pid},
			"nonce": str(_nonce_counter),
		}
		if _uds != null:
			_uds.put_data(encode_frame(OP_FRAME, clear_payload))
			_uds.put_data(encode_frame(OP_CLOSE, {}))
		elif _pipe != null:
			_pipe.store_buffer(encode_frame(OP_FRAME, clear_payload))
			_pipe.store_buffer(encode_frame(OP_CLOSE, {}))
			_pipe.flush()

	if _uds != null:
		_uds.disconnect_from_host()
		_uds = null
	if _pipe != null:
		_pipe.close()
		_pipe = null

	_mutex.lock()
	_next_connect_attempt = Time.get_unix_time_from_system() + RECONNECT_BACKOFF_SEC
	_mutex.unlock()


func _read_uds_frame(uds: StreamPeerUDS, wait_iters: int) -> Dictionary:
	for _i in maxi(1, wait_iters + 1):
		uds.poll()
		if uds.get_available_bytes() >= 8:
			break
		if wait_iters <= 0:
			return {}
		OS.delay_msec(20)
	if uds.get_available_bytes() < 8:
		return {}
	var hdr_res: Array = uds.get_data(8)
	if int(hdr_res[0]) != OK:
		return {}
	var hdr: PackedByteArray = hdr_res[1] as PackedByteArray
	var body_len: int = hdr.decode_u32(4)
	if body_len <= 0 or body_len > 65536:
		return {}
	for _i in 20:
		uds.poll()
		if uds.get_available_bytes() >= body_len:
			break
		OS.delay_msec(10)
	if uds.get_available_bytes() < body_len:
		return {}
	var body_res: Array = uds.get_data(body_len)
	if int(body_res[0]) != OK:
		return {}
	var parsed: Variant = JSON.parse_string((body_res[1] as PackedByteArray).get_string_from_utf8())
	return parsed as Dictionary if parsed is Dictionary else {}


func _read_pipe_frame(pipe: FileAccess) -> Dictionary:
	var hdr: PackedByteArray = pipe.get_buffer(8)
	if hdr.size() < 8:
		return {}
	var body_len: int = hdr.decode_u32(4)
	if body_len <= 0 or body_len > 65536:
		return {}
	var body: PackedByteArray = pipe.get_buffer(body_len)
	if body.size() < body_len:
		return {}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	return parsed as Dictionary if parsed is Dictionary else {}
