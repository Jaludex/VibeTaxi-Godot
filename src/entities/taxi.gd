class_name Taxi
extends CarBase

## Player taxi with Mouse/Keyboard/Gamepad steering, Vibe Mode drifting, ghost trail, and engine audio.

signal vibe_changed(is_vibe: bool)
signal damaged(amount: float, remaining_health: float)

enum State { IDLE, DRIVE, VIBE, CRASHED }

var current_state: State = State.IDLE
var vibe_color: Color = Color(50.0 / 255.0, 1.0, 1.0)

var is_accelerating: bool = false
var is_braking: bool = false
var is_drifting: bool = false
var target_position: Vector2 = Vector2.ZERO
var touch_controls: TouchControls = null

var _slide_velocity: Vector2 = Vector2.ZERO
var _ghost_timer: float = 0.0
var _skid_last_l: Vector2 = Vector2.INF
var _skid_last_r: Vector2 = Vector2.INF
var _car_damage_cooldown: float = 0.0

var _engine_players: Dictionary = {}
@onready var _drift_smoke_l: CPUParticles2D = $DriftSmokeL
@onready var _drift_smoke_r: CPUParticles2D = $DriftSmokeR
@onready var _engine_smoke: CPUParticles2D = $EngineSmoke


func _ready() -> void:
	if vehicle_def == null:
		apply_vehicle_def("yellow_taxi")
		max_health = GameConstants.TAXI_MAX_HEALTH
		health = GameConstants.TAXI_MAX_HEALTH
	super._ready()
	target_position = global_position
	_setup_engine_audio()


func attach_to_map(map: CityMap) -> void:
	attach_silhouette(map)


func _setup_engine_audio() -> void:
	var node_map: Dictionary = {
		"idle_normal": $EngineAudio/IdleNormal,
		"idle_damaged": $EngineAudio/IdleDamaged,
		"engine1": $EngineAudio/Engine1,
		"engine2": $EngineAudio/Engine2,
		"drifting": $EngineAudio/Drifting,
	}
	for key_var in node_map.keys():
		var key: String = str(key_var)
		var player: AudioStreamPlayer = node_map[key] as AudioStreamPlayer
		if player == null or player.stream == null:
			continue
		if player.stream is AudioStreamWAV:
			var wav: AudioStreamWAV = player.stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			if wav.loop_end <= 0:
				wav.loop_end = maxi(1, int(round(wav.get_length() * float(wav.mix_rate))))
		player.volume_db = -80.0
		player.play()
		_engine_players[key] = player


func is_vibe_mode() -> bool:
	return current_state == State.VIBE


func set_vibe_mode(enabled: bool) -> void:
	if is_crashed:
		return
	var target: State = State.VIBE if enabled else (State.DRIVE if absf(speed) > 0.1 or is_accelerating else State.IDLE)
	if target == current_state:
		return
	_change_state(target)


func reset_inputs() -> void:
	is_accelerating = false
	is_braking = false
	is_drifting = false
	if current_state == State.DRIVE:
		_change_state(State.IDLE)


func stop_immediately() -> void:
	reset_inputs()
	speed = 0.0
	velocity = Vector2.ZERO
	_slide_velocity = Vector2.ZERO


func _change_state(new_state: State) -> void:
	var was_vibe: bool = current_state == State.VIBE
	if was_vibe and new_state != State.VIBE:
		_drift_smoke_l.emitting = false
		_drift_smoke_r.emitting = false
		_skid_last_l = Vector2.INF
		_skid_last_r = Vector2.INF

	current_state = new_state
	if new_state == State.VIBE:
		_slide_velocity = velocity
		if not was_vibe:
			vibe_changed.emit(true)
	elif was_vibe:
		vibe_changed.emit(false)


func _physics_process(delta: float) -> void:
	if _car_damage_cooldown > 0.0:
		_car_damage_cooldown = maxf(0.0, _car_damage_cooldown - delta)
	decay_push(delta)
	_poll_inputs()

	match current_state:
		State.IDLE:
			_drift_smoke_l.emitting = false
			_drift_smoke_r.emitting = false
			if (is_accelerating or is_braking) and not prevent_movement:
				_change_state(State.DRIVE)
			else:
				speed = move_toward(speed, 0.0, friction * delta)
				velocity = Vector2(cos(heading_angle), sin(heading_angle)) * speed
				perform_move_and_detect()
		State.DRIVE:
			is_drifting = false
			var moving: bool = step_driving(delta, target_position, is_accelerating, is_braking)
			perform_move_and_detect()
			_sync_speed_from_slide()
			if not moving:
				_change_state(State.IDLE)
		State.VIBE:
			var eff_max: float = max_speed * GameConstants.TAXI_VIBE_SPEED_MULT
			var eff_accel: float = acceleration * GameConstants.TAXI_VIBE_ACCEL_MULT
			var eff_turn: float = turn_speed * (GameConstants.TAXI_DRIFT_TURN_MULT if is_drifting else 1.0)
			step_driving(delta, target_position, is_accelerating, is_braking, eff_max, eff_accel, eff_turn)

			var ideal_vel: Vector2 = velocity
			var grip: float = GameConstants.TAXI_DRIFT_GRIP if is_drifting else GameConstants.TAXI_VIBE_GRIP
			_slide_velocity += (ideal_vel - _slide_velocity) * minf(1.0, grip * delta)

			if is_drifting:
				var cur_spd: float = _slide_velocity.length()
				var ideal_spd: float = absf(speed)
				if cur_spd > 0.1 and ideal_spd > 0.1:
					var ratio: float = (ideal_spd * 0.95) / cur_spd
					if ratio > 1.0:
						_slide_velocity *= ratio

			velocity = _slide_velocity
			perform_move_and_detect()
			_slide_velocity = velocity
			_update_drift_effects()
			_update_ghosting(delta)
		State.CRASHED:
			_drift_smoke_l.emitting = false
			_drift_smoke_r.emitting = false
			speed = move_toward(speed, 0.0, friction * 1.5 * delta)
			velocity = Vector2(cos(heading_angle), sin(heading_angle)) * speed
			perform_move_and_detect()

	_update_engine_smoke()
	_update_engine_audio()
	update_silhouette()


func _poll_inputs() -> void:
	if is_crashed:
		is_accelerating = false
		is_braking = false
		is_drifting = false
		return

	var touch_active: bool = touch_controls != null and touch_controls.visible
	is_braking = Input.is_action_pressed("brake") or (touch_active and touch_controls.is_brake_pressed())
	is_drifting = (Input.is_action_pressed("drift") or (touch_active and touch_controls.is_drift_pressed())) and current_state == State.VIBE

	var dz: float = float(ConfigManager.get_value("gamepad_deadzone", 0.25))
	var pad_vec: Vector2 = _read_gamepad_vector(dz)
	var key_vec: Vector2 = Vector2(
		float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))
	)

	if pad_vec.length() > 0.0:
		is_accelerating = true
		target_position = global_position + pad_vec * GameConstants.MOUSE_MAX_SPEED_RADIUS
	elif key_vec != Vector2.ZERO:
		is_accelerating = true
		target_position = global_position + key_vec.normalized() * GameConstants.MOUSE_MAX_SPEED_RADIUS
	elif touch_active:
		var t_vec: Vector2 = touch_controls.get_joystick_vector()
		if t_vec.length() > 0.0:
			is_accelerating = true
			target_position = global_position + t_vec * GameConstants.MOUSE_MAX_SPEED_RADIUS
		elif touch_controls.is_drag_accelerating():
			is_accelerating = true
			target_position = get_canvas_transform().affine_inverse() * touch_controls.get_drag_screen_pos()
		else:
			is_accelerating = false
	else:
		is_accelerating = Input.is_action_pressed("accelerate")
		target_position = get_global_mouse_position()


func _read_gamepad_vector(dz: float) -> Vector2:
	var raw: Vector2 = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	var mag: float = raw.length()
	if mag < dz:
		return Vector2.ZERO
	var normalized_mag: float = clampf((mag - dz) / maxf(0.01, 1.0 - dz), 0.0, 1.0)
	return raw.normalized() * normalized_mag


func _sync_speed_from_slide() -> void:
	var actual_len: float = velocity.length()
	if actual_len < absf(speed) - 20.0:
		speed = actual_len * (1.0 if speed >= 0.0 else -1.0)


func _on_new_collision(collider: Object, normal: Vector2) -> void:
	super._on_new_collision(collider, normal)
	if collider is PropEntity:
		penalize_speed(0.5)
		(collider as PropEntity).on_hit_by_vehicle(self, -normal)
		if city_map != null and not city_map.muted:
			AudioManager.play_sfx("crash_solid", 0.2)
	elif collider is CarBase:
		var other_car: CarBase = collider as CarBase
		var push_vec: Vector2 = -normal * maxf(65.0, absf(speed) * 0.85)
		other_car.apply_push(push_vec)
		penalize_speed(0.75)
		if _car_damage_cooldown <= 0.0:
			_car_damage_cooldown = 0.4
			if city_map != null:
				city_map.spawn_sparks((global_position + other_car.global_position) * 0.5)
				if not city_map.muted:
					AudioManager.play_sfx("crash_car", 0.3)
			take_damage(GameConstants.CAR_CRASH_DAMAGE)
		if other_car.has_method("on_vehicle_collision"):
			other_car.call("on_vehicle_collision", self)
	elif collider is StaticBody2D:
		if absf(speed) > GameConstants.WALL_CRASH_MIN_SPEED:
			if city_map != null:
				city_map.spawn_sparks(global_position)
				if not city_map.muted:
					AudioManager.play_sfx("crash_wall", 0.3)
			take_damage(GameConstants.WALL_CRASH_DAMAGE)


func penalize_speed(factor: float = 0.5) -> void:
	super.penalize_speed(factor)
	_slide_velocity *= factor


func take_damage(amount: float) -> void:
	if invincible or is_crashed or health <= 0.0:
		return
	var final_amount: float = amount * (GameConstants.TAXI_VIBE_DAMAGE_MULT if current_state == State.VIBE else 1.0)
	var before: float = health
	super.take_damage(final_amount)
	if health < before:
		damaged.emit(before - health, health)
	if is_crashed:
		_change_state(State.CRASHED)


func _update_drift_effects() -> void:
	var drifting_fast: bool = is_drifting and _slide_velocity.length() >= 30.0
	_drift_smoke_l.emitting = drifting_fast
	_drift_smoke_r.emitting = drifting_fast
	if not drifting_fast or city_map == null:
		_skid_last_l = Vector2.INF
		_skid_last_r = Vector2.INF
		return

	var cos_a: float = cos(heading_angle)
	var sin_a: float = sin(heading_angle)
	var right_vec: Vector2 = Vector2(-sin_a, cos_a)
	var back_vec: Vector2 = Vector2(cos_a, sin_a)
	var wl: Vector2 = global_position - back_vec * 10.0 - right_vec * 5.0
	var wr: Vector2 = global_position - back_vec * 10.0 + right_vec * 5.0

	var should_skid: bool = (
		_skid_last_l == Vector2.INF
		or wl.distance_to(_skid_last_l) >= 4.0
		or wr.distance_to(_skid_last_r) >= 4.0
	)
	if should_skid:
		_spawn_skid_mark(wl)
		_spawn_skid_mark(wr)
		_skid_last_l = wl
		_skid_last_r = wr


func _spawn_skid_mark(world_pos: Vector2) -> void:
	var ground: Node2D = city_map.get_ground_effects()
	if ground.has_method("add_mark"):
		ground.call("add_mark", world_pos)


func _update_ghosting(delta: float) -> void:
	if city_map == null or _slide_velocity.length() < 50.0:
		return
	_ghost_timer += delta
	if _ghost_timer < GameConstants.GHOSTING_SPAWN_RATE:
		return
	_ghost_timer = 0.0

	var ghost: Sprite2D = Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.region_enabled = true
	ghost.region_rect = sprite.region_rect
	ghost.global_position = global_position
	ghost.rotation = rotation
	ghost.z_index = 5
	ghost.modulate = Color(vibe_color.r, vibe_color.g, vibe_color.b, GameConstants.GHOSTING_ALPHA_START)
	city_map.get_entities_root().add_child(ghost)
	var tween: Tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, GameConstants.GHOSTING_DURATION)
	tween.tween_callback(ghost.queue_free)


func _update_engine_smoke() -> void:
	if _engine_smoke == null:
		return
	var threshold: float = max_health * 0.6
	if health >= threshold:
		_engine_smoke.emitting = false
		return
	_engine_smoke.emitting = true
	var ratio: float = clampf(health / threshold, 0.0, 1.0)
	_engine_smoke.color = Color(0.2, 0.2, 0.2, 0.85) if ratio < 0.2 else Color(0.5, 0.5, 0.5, 0.7)


func _update_engine_audio() -> void:
	if _engine_players.is_empty():
		return
	if is_crashed:
		for player in _engine_players.values():
			(player as AudioStreamPlayer).volume_db = -80.0
		return

	var eff_max: float = max_speed * (GameConstants.TAXI_VIBE_SPEED_MULT if current_state == State.VIBE else 1.0)
	var speed_ratio: float = clampf(absf(speed) / maxf(1.0, eff_max), 0.0, 1.0)
	var is_damaged: bool = health <= GameConstants.TAXI_DAMAGED_ENGINE_HEALTH

	var v_idle: float = 0.0
	var v_eng1: float = 0.0
	var v_eng2: float = 0.0
	if speed_ratio < 0.3:
		var t: float = speed_ratio / 0.3
		v_idle = 1.0 - t
		v_eng1 = t
	elif speed_ratio < 0.8:
		v_eng1 = 1.0
	else:
		var t: float = (speed_ratio - 0.8) / 0.2
		v_eng1 = 1.0 - t
		v_eng2 = t

	_set_engine_vol("idle_damaged" if is_damaged else "idle_normal", v_idle * 0.35)
	_set_engine_vol("idle_normal" if is_damaged else "idle_damaged", 0.0)
	_set_engine_vol("engine1", v_eng1 * 0.35)
	_set_engine_vol("engine2", v_eng2 * 0.35)
	var drifting_snd: float = 0.35 if (is_drifting and absf(speed) > 30.0) else 0.0
	_set_engine_vol("drifting", drifting_snd)


func _set_engine_vol(key: String, linear: float) -> void:
	if not _engine_players.has(key):
		return
	var player: AudioStreamPlayer = _engine_players[key] as AudioStreamPlayer
	if linear <= 0.001:
		player.volume_db = -80.0
	else:
		player.volume_db = linear_to_db(linear)
		if not player.playing:
			player.play()


func get_binding_texts() -> Dictionary:
	var dev: String = "touch" if ConfigManager.is_touch_controls_enabled() else GameFlow.last_input_device
	if dev == "touch":
		var mode: String = str(ConfigManager.get_value("touch_mode", "joystick"))
		return {
			"drive_btn": I18n.t("input_touch_drag_drive" if mode == "drag" else "input_touch_joy_drive"),
			"steer_btn": I18n.t("input_touch_drag_steer" if mode == "drag" else "input_touch_joy_steer"),
			"brake_btn": I18n.t("input_touch_brake"),
			"pause_btn": I18n.t("input_touch_pause"),
			"radio_vol": I18n.t("input_touch_radio_vol"),
			"radio_station": I18n.t("input_touch_radio_station"),
			"drift_btn": I18n.t("input_touch_drift"),
		}
	if dev == "gamepad":
		return {
			"drive_btn": I18n.t("input_pad_drive"),
			"steer_btn": I18n.t("input_pad_steer"),
			"brake_btn": I18n.t("input_pad_brake"),
			"pause_btn": I18n.t("input_pad_pause"),
			"radio_vol": I18n.t("input_pad_radio_vol"),
			"radio_station": I18n.t("input_pad_radio_station"),
			"drift_btn": I18n.t("input_pad_drift"),
		}
	if dev == "keyboard":
		return {
			"drive_btn": I18n.t("input_key_drive"),
			"steer_btn": I18n.t("input_key_steer"),
			"brake_btn": I18n.t("input_kb_brake"),
			"pause_btn": I18n.t("input_kb_pause"),
			"radio_vol": I18n.t("input_kb_radio_vol"),
			"radio_station": I18n.t("input_kb_radio_station"),
			"drift_btn": I18n.t("input_kb_drift"),
		}
	return {
		"drive_btn": I18n.t("input_mouse_drive"),
		"steer_btn": I18n.t("input_mouse_steer"),
		"brake_btn": I18n.t("input_kb_brake"),
		"pause_btn": I18n.t("input_kb_pause"),
		"radio_vol": I18n.t("input_kb_radio_vol"),
		"radio_station": I18n.t("input_kb_radio_station"),
		"drift_btn": I18n.t("input_kb_drift"),
	}
