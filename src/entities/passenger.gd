class_name Passenger
extends Node2D

## Rideable passenger with comfort/music matching, walking transitions, and Safe bonus tracking.

signal comfort_changed(new_comfort: float)
signal dialogue_requested(text: String)
signal crash_reacted

enum State { WAIT, WALK, RIDE }

var current_state: State = State.WAIT
var def_key: String = "pedestrian_1"
var destination_name: String = ""
var destination_pos: Vector2 = Vector2.ZERO
var pickup_pos: Vector2 = Vector2.ZERO
var trip_color: Color = GameConstants.COLOR_TRIP_SHORT
var music_preference: String = ""

var comfort: float = 55.0
var time_riding: float = 0.0
var damage_taken: float = 0.0
var has_initial_music_reacted: bool = false
var _bad_music_timer: float = 0.0

var dialogues: Dictionary = {}
var _idle_frames: Array = [0, 1]
var _walk_frames: Array = [2, 3, 4, 5]
var _active_frames: Array = []
var _anim_timer: float = 0.0
var _anim_interval: float = 0.4
var _anim_idx: int = 0

var _walk_target_node: Node2D = null
var _walk_target_pos: Vector2 = Vector2.ZERO
var _walk_callback: Callable = Callable()

@onready var sprite: Sprite2D = $Sprite2D
@onready var _pickup_circle: Node2D = $PickupCircle


func setup(pos: Vector2, p_dest_name: String, p_dest_pos: Vector2, p_def_key: String = "", p_music_pref: String = "", p_valid_genres: Array[String] = []) -> void:
	global_position = pos
	pickup_pos = pos
	destination_name = p_dest_name
	destination_pos = p_dest_pos

	var dist: float = pos.distance_to(p_dest_pos)
	if dist < 800.0:
		trip_color = GameConstants.COLOR_TRIP_SHORT
	elif dist < 2000.0:
		trip_color = GameConstants.COLOR_TRIP_MEDIUM
	else:
		trip_color = GameConstants.COLOR_TRIP_LONG

	var keys: Array = GameConstants.PASSENGER_DEFS.keys()
	def_key = p_def_key if GameConstants.PASSENGER_DEFS.has(p_def_key) else str(keys[randi() % keys.size()])
	var def: Dictionary = GameConstants.PASSENGER_DEFS[def_key] as Dictionary
	_idle_frames = def["idle"] as Array
	_walk_frames = def["walk"] as Array

	if not p_music_pref.is_empty():
		music_preference = p_music_pref
	else:
		var valid_genres: Array[String] = p_valid_genres.duplicate()
		if valid_genres.is_empty():
			var files: PackedStringArray = ResourceLoader.list_directory("res://resources/radio")
			if files.is_empty():
				var dir: DirAccess = DirAccess.open("res://resources/radio")
				if dir != null:
					files = dir.get_files()
			for raw_name in files:
				var fname: String = raw_name.trim_suffix(".remap")
				if fname.ends_with(".tres"):
					var st: RadioStationDef = load("res://resources/radio/" + fname) as RadioStationDef
					if st != null and st.genre != "off" and not (st.genre in valid_genres):
						valid_genres.append(st.genre)
		if not valid_genres.is_empty():
			music_preference = valid_genres[randi() % valid_genres.size()]

	comfort = float(randi_range(
		int(GameConstants.COMFORT_RULES["initial_min"]),
		int(GameConstants.COMFORT_RULES["initial_max"])
	))
	_refresh_dialogues()


func _refresh_dialogues() -> void:
	var greeting: String = I18n.pick_dialogue("enter", "", {"destination": destination_name})
	var hint: String = I18n.pick_dialogue("hints", music_preference)
	dialogues = {
		"enter": ("%s %s" % [greeting, hint]).strip_edges(),
		"reaction_good": I18n.pick_dialogue("reaction", "good"),
		"reaction_neutral": I18n.pick_dialogue("reaction", "neutral"),
		"reaction_bad": I18n.pick_dialogue("reaction", "bad"),
		"exit_good": I18n.pick_dialogue("exit", "good"),
		"exit_bad": I18n.pick_dialogue("exit", "bad"),
	}


func _ready() -> void:
	_pickup_circle.draw.connect(_draw_pickup_circle)
	_set_anim("idle")
	_redraw_pickup_circle()


func _process(delta: float) -> void:
	if not _active_frames.is_empty():
		_anim_timer += delta
		if _anim_timer >= _anim_interval:
			_anim_timer = fmod(_anim_timer, _anim_interval)
			_anim_idx = (_anim_idx + 1) % _active_frames.size()
			sprite.frame = int(_active_frames[_anim_idx])

	if current_state == State.WALK:
		var dest: Vector2 = _walk_target_node.global_position if is_instance_valid(_walk_target_node) else _walk_target_pos
		var diff: Vector2 = dest - global_position
		if diff.x != 0.0:
			sprite.flip_h = diff.x < 0.0
		var step: float = GameConstants.PASSENGER_WALK_SPEED * delta
		if diff.length() <= step or diff.length() < 4.0:
			global_position = dest
			var cb: Callable = _walk_callback
			_walk_callback = Callable()
			if cb.is_valid():
				cb.call()
		else:
			global_position += diff.normalized() * step


func start_walk_to_node(node: Node2D, on_arrival: Callable) -> void:
	current_state = State.WALK
	_walk_target_node = node
	_walk_callback = on_arrival
	visible = true
	_set_anim("walk")
	_redraw_pickup_circle()


func start_walk_to_pos(pos: Vector2, on_arrival: Callable) -> void:
	current_state = State.WALK
	_walk_target_node = null
	_walk_target_pos = pos
	_walk_callback = on_arrival
	visible = true
	_set_anim("walk")
	_redraw_pickup_circle()


func start_ride() -> void:
	current_state = State.RIDE
	visible = false
	_set_anim("idle")
	_redraw_pickup_circle()


func update_comfort(delta: float, current_genre: String) -> void:
	if current_state != State.RIDE:
		return

	time_riding += delta
	var is_correct: bool = (current_genre == music_preference)

	if not has_initial_music_reacted:
		if is_correct and time_riding <= float(GameConstants.COMFORT_RULES["initial_reaction_time"]):
			comfort = minf(
				float(GameConstants.COMFORT_RULES["max_comfort"]),
				comfort + float(GameConstants.COMFORT_RULES["initial_reaction_bonus"])
			)
			has_initial_music_reacted = true
			comfort_changed.emit(comfort)
			dialogue_requested.emit(I18n.pick_dialogue("reaction", "good"))
		elif time_riding > float(GameConstants.COMFORT_RULES["initial_reaction_time"]):
			has_initial_music_reacted = true

	var prev: float = comfort
	if is_correct:
		_bad_music_timer = 0.0
		comfort = minf(
			float(GameConstants.COMFORT_RULES["max_comfort"]),
			comfort + float(GameConstants.COMFORT_RULES["comfort_increase_rate"]) * delta
		)
	else:
		_bad_music_timer += delta
		if _bad_music_timer >= GameConstants.BAD_MUSIC_PENALTY_TIME:
			comfort = maxf(
				float(GameConstants.COMFORT_RULES["min_comfort"]),
				comfort - float(GameConstants.COMFORT_RULES["comfort_decrease_rate"]) * delta
			)

	if not is_equal_approx(comfort, prev):
		comfort_changed.emit(comfort)


func on_collision(dmg_amount: float = 1.0) -> void:
	damage_taken += maxf(0.1, dmg_amount)
	comfort = maxf(
		float(GameConstants.COMFORT_RULES["min_comfort"]),
		comfort - float(GameConstants.COMFORT_RULES["collision_penalty"])
	)
	comfort_changed.emit(comfort)
	crash_reacted.emit()
	dialogue_requested.emit(I18n.pick_dialogue("reaction", "bad"))


func get_current_frame_index() -> int:
	return sprite.frame if sprite != null else 0


func is_waiting() -> bool:
	return current_state == State.WAIT


func is_walking() -> bool:
	return current_state == State.WALK


func is_riding() -> bool:
	return current_state == State.RIDE


func _set_anim(anim_name: String) -> void:
	var frames: Array = _walk_frames if anim_name == "walk" else _idle_frames
	var interval: float = 0.15 if anim_name == "walk" else 0.4
	if _active_frames == frames:
		return
	_active_frames = frames
	_anim_interval = interval
	_anim_timer = 0.0
	_anim_idx = 0
	if sprite != null and not _active_frames.is_empty():
		sprite.frame = int(_active_frames[0])


func _redraw_pickup_circle() -> void:
	if _pickup_circle != null:
		_pickup_circle.queue_redraw()


func _draw_pickup_circle() -> void:
	if current_state == State.WAIT:
		_pickup_circle.draw_arc(Vector2.ZERO, GameConstants.PASSENGER_DETECTION_RADIUS, 0.0, TAU, 36, Color.YELLOW, 2.0)
