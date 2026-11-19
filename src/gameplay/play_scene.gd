class_name PlayScene
extends Node2D

## Main gameplay scene orchestrating CityMap, Taxi, AI systems, RuleStrategy, and HUD.

const PASSENGER_SCENE: PackedScene = preload("res://src/entities/passenger.tscn")

@onready var _city_map: CityMap = $CityMap
@onready var _traffic_system: TrafficSystem = $TrafficSystem
@onready var _pedestrian_system: PedestrianSystem = $PedestrianSystem
@onready var _camera: CameraRig = $CameraRig
@onready var _hud_layer: CanvasLayer = $HUDLayer
@onready var _vibe_tint: ColorRect = $HUDLayer/VibeTint
@onready var _taximeter_box: Control = $HUDLayer/TaximeterBox
@onready var _time_title: Label = $HUDLayer/TaximeterBox/TaximeterSprite/TimeTitle
@onready var _time_value: Label = $HUDLayer/TaximeterBox/TaximeterSprite/TimeValue
@onready var _counter_value: Label = $HUDLayer/TaximeterBox/CounterValue
@onready var _counter_label: Label = $HUDLayer/TaximeterBox/CounterLabel
@onready var _side_popup: Label = $HUDLayer/TaximeterBox/SidePopup
@onready var _mode_badge: Label = $HUDLayer/ModeBadge
@onready var _center_popup: Label = $HUDLayer/CenterPopup
@onready var _danger_label: Label = $HUDLayer/DangerLabel
@onready var _arrow: DestinationArrow = $HUDLayer/DestinationArrow
@onready var _radio: RadioTuner = $HUDLayer/RadioTuner
@onready var _passenger_hud: PassengerHUD = $HUDLayer/PassengerHUD
@onready var _touch_controls: TouchControls = $HUDLayer/TouchControls
@onready var _intro_fade: ColorRect = $HUDLayer/IntroFade
@onready var _start_label: Label = $HUDLayer/StartLabel

var rule_strategy: RuleStrategy = null
var taxi: Taxi = null
var active_passenger: Passenger = null
var waiting_passengers: Array[Passenger] = []

var tutorial_mode: bool = false
var _tutorial_step: int = 1
var _tutorial_vibe_shown: bool = false
var _tutorial_initial_time: float = 0.0

var _is_dedicated_tutorial: bool = false
var _tutorial_triggers: Array[Dictionary] = []
var _last_checkpoint: Vector2 = Vector2.ZERO
var _tutorial_paused: bool = false
var _tutorial_completed: bool = false

var _display_counter: float = 0.0
var _counter_is_money: bool = false
var _counter_format_key: String = ""
var _counter_param: String = ""

var _game_over_triggered: bool = false
var _was_vibe: bool = false
var _danger_timer: float = 0.0
@onready var _delivery_circle: Node2D = $DeliveryCircle
@onready var _mouse_particles: CPUParticles2D = $MouseParticles


func _ready() -> void:
	_setup_fonts()
	var params: Dictionary = GameFlow.pending_play_params.duplicate(true)
	GameFlow.pending_play_params.clear()
	_initialize_run(params)


func _setup_fonts() -> void:
	_hud_layer.visible = true
	_danger_label.text = I18n.t("hud_danger")
	_time_title.text = I18n.t("hud_time")


func _initialize_run(params: Dictionary) -> void:
	var mode: String = str(params.get("mode", "arcade"))
	_is_dedicated_tutorial = (mode == "tutorial")
	tutorial_mode = bool(params.get("tutorial_mode", false)) and not _is_dedicated_tutorial

	match mode:
		"workday":
			rule_strategy = WorkdayStrategy.new(
				float(params.get("time_limit", GameConstants.WORKDAY_TIME_LIMIT)),
				float(params.get("money", 0.0)),
				int(params.get("day", 1)),
				bool(params.get("is_loaded_run", false))
			)
		"zen":
			rule_strategy = ZenStrategy.new()
		"tutorial":
			rule_strategy = TutorialStrategy.new()
		_:
			rule_strategy = ArcadeStrategy.new()

	var map_key: String = "tutorial" if _is_dedicated_tutorial else "city"
	_city_map.load_map(map_key, true)

	var spawn_pos: Vector2 = _city_map.get_random_taxi_spawn()
	var taxi_scene: PackedScene = load("res://src/entities/taxi.tscn") as PackedScene
	taxi = taxi_scene.instantiate() as Taxi
	taxi.global_position = spawn_pos
	_city_map.get_entities_root().add_child(taxi)
	taxi.attach_to_map(_city_map)
	taxi.invincible = rule_strategy.invincible
	if params.has("taxi_health"):
		taxi.health = clampf(float(params["taxi_health"]), 1.0, taxi.max_health)
	taxi.damaged.connect(_on_taxi_damaged)
	taxi.vibe_changed.connect(_on_taxi_vibe_changed)

	_camera.set_bounds(_city_map.get_map_rect())
	_camera.follow_target = taxi
	_camera.snap_to(taxi.global_position)

	_traffic_system.setup(_city_map)
	_traffic_system.camera_ref = _camera

	if not _is_dedicated_tutorial:
		_pedestrian_system.setup(_city_map, _traffic_system)
		_pedestrian_system.camera_ref = _camera
		_pedestrian_system.taxi_ref = taxi
		_pedestrian_system.taxi_hit_pedestrian.connect(_on_taxi_hit_pedestrian)
	else:
		_pedestrian_system.set_process(false)

	_passenger_hud.taxi_ref = taxi
	_passenger_hud.visible = rule_strategy.has_hud
	if _touch_controls != null:
		_touch_controls.radio_ref = _radio
		taxi.touch_controls = _touch_controls
		if not _touch_controls.pause_requested.is_connected(_open_pause_menu):
			_touch_controls.pause_requested.connect(_open_pause_menu)
		if not _touch_controls.radio_prev_requested.is_connected(_radio.prev_station):
			_touch_controls.radio_prev_requested.connect(_radio.prev_station)
		if not _touch_controls.radio_next_requested.is_connected(_radio.next_station):
			_touch_controls.radio_next_requested.connect(_radio.next_station)

	_setup_hud_for_rule()

	if _is_dedicated_tutorial:
		_create_tutorial_passengers()
		_tutorial_triggers = _city_map.tutorial_triggers.duplicate(true)
		_last_checkpoint = taxi.global_position
	else:
		_generate_passengers(0.5)

	if tutorial_mode:
		_tutorial_step = 1
		_tutorial_vibe_shown = false
		_tutorial_initial_time = rule_strategy.time_remaining

	AudioManager.start_ambient("city_soundscape", 0.5)
	AudioManager.play_sfx("engine_start", 0.4, &"Engine")

	_play_intro_banner()


func _setup_hud_for_rule() -> void:
	_taximeter_box.visible = rule_strategy.has_timer
	_mode_badge.visible = not rule_strategy.has_timer
	if _mode_badge.visible:
		if rule_strategy is ZenStrategy:
			_mode_badge.text = I18n.t("hud_zen")
			_mode_badge.add_theme_color_override("font_color", Color(0.78, 1.0, 0.78))
		else:
			_mode_badge.text = I18n.t("hud_tutorial")
			_mode_badge.add_theme_color_override("font_color", Color(0.39, 1.0, 1.0))

	var info: Dictionary = rule_strategy.get_hud_counter_text()
	if not info.is_empty():
		_display_counter = float(info["value"])
		_counter_is_money = bool(info["is_money"])
		_counter_format_key = str(info["format_key"])
		_counter_param = str(info["param"])
		_counter_label.text = str(info["label"])
		_counter_value.add_theme_color_override("font_color", info["color"] as Color)
		_counter_label.add_theme_color_override("font_color", info["color"] as Color)
		_refresh_counter_label()


func _play_intro_banner() -> void:
	_intro_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_start_label.text = rule_strategy.get_start_text()
	_start_label.modulate.a = 0.0

	var tween: Tween = create_tween()
	tween.tween_property(_intro_fade, "color:a", 0.0, 1.0)
	tween.parallel().tween_property(_start_label, "modulate:a", 1.0, 1.0)
	tween.tween_interval(2.0)
	tween.tween_property(_start_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void:
		if tutorial_mode and not _game_over_triggered:
			_show_tutorial_dialog(I18n.t("tutorial_title"), I18n.t(_get_integrated_key("welcome")))
	)


func _get_integrated_key(step: String) -> String:
	var use_touch: bool = ConfigManager.is_touch_controls_enabled() or GameFlow.last_input_device == "touch"
	if not use_touch:
		return "tutorial_integrated_" + step
	if step == "welcome":
		var mode: String = str(ConfigManager.get_value("touch_mode", "joystick"))
		return "tutorial_integrated_welcome_touch_drag" if mode == "drag" else "tutorial_integrated_welcome_touch_joy"
	return "tutorial_integrated_" + step + "_touch"


func _process(delta: float) -> void:
	if _game_over_triggered or _tutorial_paused:
		return

	rule_strategy.update_rule(delta)
	if tutorial_mode:
		rule_strategy.time_remaining = _tutorial_initial_time

	if rule_strategy.should_respawn_passengers(waiting_passengers.size()):
		_generate_passengers(0.3)

	if rule_strategy.always_vibe and taxi.health > 0.0 and not taxi.is_vibe_mode():
		taxi.set_vibe_mode(true)

	if taxi.health <= 0.0 or rule_strategy.game_over:
		_trigger_end_of_run()
		return

	_update_ambient_ducking()
	_update_mouse_particles()
	_update_passengers(delta)
	_update_hud_displays(delta)
	if _touch_controls != null and taxi != null:
		var vibe_now: bool = taxi.is_vibe_mode()
		if _touch_controls.taxi_vibe_active != vibe_now:
			_touch_controls.taxi_vibe_active = vibe_now
			_touch_controls.queue_redraw()

	if _is_dedicated_tutorial:
		_check_tutorial_triggers()
		_check_tutorial_completion()


func _unhandled_input(event: InputEvent) -> void:
	if _game_over_triggered or _tutorial_paused:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_open_pause_menu()


func request_focus_pause() -> void:
	if not _game_over_triggered and not GameFlow.has_modals():
		_open_pause_menu()


func _open_pause_menu() -> void:
	AudioManager.play_sfx("pause")
	taxi.reset_inputs()
	var pause_scene: PackedScene = load("res://src/menus/pause_menu.tscn") as PackedScene
	GameFlow.push_modal(pause_scene.instantiate() as Control, true)


func _update_ambient_ducking() -> void:
	var base_vol: float = 0.5 if _radio.current_index == 0 else 0.1
	AudioManager.set_ambient_base_volume(base_vol)


func _update_mouse_particles() -> void:
	if _mouse_particles == null or taxi == null:
		return
	var driving: bool = taxi.is_accelerating and not taxi.prevent_movement and not taxi.is_crashed
	if driving and taxi.global_position.distance_to(taxi.target_position) > 5.0:
		_mouse_particles.global_position = taxi.target_position
		_mouse_particles.emitting = true
	else:
		_mouse_particles.emitting = false


func _update_passengers(delta: float) -> void:
	if active_passenger != null:
		if active_passenger.is_walking():
			taxi.is_accelerating = false
			taxi.prevent_movement = true
		else:
			taxi.prevent_movement = false

		if active_passenger.is_riding():
			active_passenger.update_comfort(delta, _radio.get_current_genre())
			if not rule_strategy.always_vibe:
				var should_vibe: bool = active_passenger.comfort >= float(GameConstants.COMFORT_RULES["vibe_threshold"])
				if should_vibe != taxi.is_vibe_mode():
					taxi.set_vibe_mode(should_vibe)

			if tutorial_mode and _tutorial_step == 2 and not _tutorial_vibe_shown and taxi.is_vibe_mode():
				_tutorial_vibe_shown = true
				_show_tutorial_dialog(I18n.t("tutorial_title"), I18n.t(_get_integrated_key("vibe")))

			var dest_pos: Vector2 = active_passenger.destination_pos
			var dist: float = taxi.global_position.distance_to(dest_pos)
			if dist <= GameConstants.PASSENGER_DELIVERY_RADIUS and absf(taxi.speed) < GameConstants.PASSENGER_STOP_SPEED_THRESHOLD:
				_deliver_active_passenger()
	else:
		taxi.prevent_movement = false
		for p in waiting_passengers:
			if not is_instance_valid(p) or not p.is_waiting():
				continue
			if taxi.global_position.distance_to(p.global_position) <= GameConstants.PASSENGER_DETECTION_RADIUS and absf(taxi.speed) < GameConstants.PASSENGER_STOP_SPEED_THRESHOLD:
				_pickup_passenger(p)
				break


func _pickup_passenger(p: Passenger) -> void:
	AudioManager.play_sfx("honk")
	waiting_passengers.erase(p)
	active_passenger = p
	p.pickup_pos = p.global_position
	p.z_index = 6
	p.start_walk_to_node(taxi, func() -> void:
		if not is_instance_valid(p) or _game_over_triggered:
			return
		p.z_index = 5
		p.start_ride()
		_delivery_circle.global_position = p.destination_pos
		_delivery_circle.visible = true
		_arrow.activate(p.destination_pos, true)

		if tutorial_mode and _tutorial_step == 1:
			_tutorial_step = 2
			_passenger_hud.bind_passenger(p, false)
			_show_tutorial_dialog(
				I18n.t("tutorial_title"),
				I18n.t(_get_integrated_key("radio")),
				func() -> void: _passenger_hud.show_greeting()
			)
		elif rule_strategy.has_hud:
			_passenger_hud.bind_passenger(p, true)
	)


func _deliver_active_passenger() -> void:
	var p: Passenger = active_passenger
	if p == null or p.is_walking():
		return
	_delivery_circle.visible = false
	_arrow.deactivate()
	AudioManager.play_sfx("money")

	if rule_strategy.has_hud:
		_passenger_hud.unbind_passenger()

	# Spawn passenger right beside the taxi so the exit walk is visible
	p.global_position = taxi.global_position
	p.z_index = 6
	var dist_traveled: float = p.pickup_pos.distance_to(p.destination_pos)
	p.start_walk_to_pos(p.destination_pos, func() -> void:
		active_passenger = null
		taxi.prevent_movement = false
		var reward: Dictionary = rule_strategy.on_passenger_delivered(p, dist_traveled)
		_apply_delivery_feedback(reward)
		if not rule_strategy.always_vibe and taxi.is_vibe_mode():
			taxi.set_vibe_mode(false)

		if tutorial_mode and _tutorial_step == 2:
			_tutorial_step = 3
			tutorial_mode = false
			GameFlow.tutorial_enabled = false
			_show_tutorial_dialog(I18n.t("tutorial_completed_title"), I18n.t("tutorial_integrated_complete"))

		if is_instance_valid(p):
			p.queue_free()
	)


func _apply_delivery_feedback(reward: Dictionary) -> void:
	if reward.is_empty():
		return
	if bool(reward.get("bonus", false)):
		AudioManager.play_sfx("bonus")
	if reward.has("tween_target"):
		var target_val: float = float(reward["tween_target"])
		var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_method(func(v: float) -> void:
			_display_counter = v
			_refresh_counter_label()
		, _display_counter, target_val, 1.0)
	if reward.has("side_popup"):
		_show_side_popup(str(reward["side_popup"]), reward.get("side_color", Color.GREEN) as Color)
	if reward.has("center_popup"):
		_show_center_popup(str(reward["center_popup"]), reward.get("center_color", GameConstants.UI_GOLD) as Color)


func _refresh_counter_label() -> void:
	if _counter_format_key.is_empty():
		return
	var formatted_val: String = ("%.2f" % _display_counter) if _counter_is_money else str(int(round(_display_counter)))
	_counter_value.text = I18n.t(_counter_format_key, {_counter_param: formatted_val})


func _show_side_popup(text: String, color: Color) -> void:
	_side_popup.text = text
	_side_popup.add_theme_color_override("font_color", color)
	_side_popup.position = Vector2(78.0, 45.0)
	_side_popup.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_side_popup, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(_side_popup, "position:y", 25.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.0)
	tween.tween_property(_side_popup, "modulate:a", 0.0, 0.5)


func _show_center_popup(text: String, color: Color) -> void:
	_center_popup.text = text
	_center_popup.add_theme_color_override("font_color", color)
	_center_popup.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_center_popup, "modulate:a", 1.0, 0.3)
	tween.tween_interval(0.5)
	tween.tween_property(_center_popup, "modulate:a", 0.0, 0.3)


func _update_hud_displays(delta: float) -> void:
	if rule_strategy.has_timer:
		var t_rem: int = int(rule_strategy.time_remaining)
		@warning_ignore("integer_division")
		var mins: int = t_rem / 60
		var secs: int = t_rem % 60
		_time_value.text = "%02d:%02d" % [mins, secs]

	if taxi.is_vibe_mode():
		var genre: String = _radio.get_current_genre()
		var col: Color = _radio.get_station_vibe_color(genre)
		taxi.vibe_color = col
		_vibe_tint.color = Color(col.r, col.g, col.b, _vibe_tint.color.a)

	if taxi.health < taxi.max_health * 0.15:
		_danger_label.visible = true
		_danger_timer += delta
		if _danger_timer >= 0.5:
			_danger_timer = 0.0
			var cur: Color = _danger_label.get_theme_color("font_color")
			_danger_label.add_theme_color_override("font_color", Color.YELLOW if cur == Color.RED else Color.RED)
	else:
		_danger_label.visible = false

	if active_passenger != null and active_passenger.is_riding():
		_arrow.update_arrow(delta, _camera)
	elif tutorial_mode and _tutorial_step == 1 and active_passenger == null:
		var nearest: Passenger = _get_nearest_waiting_passenger()
		if nearest != null:
			_arrow.target_world_pos = nearest.global_position
			_arrow.update_arrow(delta, _camera)
		else:
			_arrow.deactivate()


func _get_nearest_waiting_passenger() -> Passenger:
	var best: Passenger = null
	var best_d: float = INF
	for p in waiting_passengers:
		if is_instance_valid(p) and p.is_waiting():
			var d: float = taxi.global_position.distance_squared_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best


func _on_taxi_damaged(amount: float, _remaining: float) -> void:
	_camera.shake(3.0, 0.2)
	if active_passenger != null and active_passenger.is_riding():
		active_passenger.on_collision(amount)


func _on_taxi_hit_pedestrian(_t: Taxi) -> void:
	if active_passenger != null and active_passenger.is_riding():
		active_passenger.on_collision(1.0)


func _on_taxi_vibe_changed(is_vibe: bool) -> void:
	if is_vibe == _was_vibe:
		return
	_was_vibe = is_vibe
	AudioManager.play_sfx("into_vibe" if is_vibe else "out_vibe")
	var target_a: float = (40.0 / 255.0) if is_vibe else 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_vibe_tint, "color:a", target_a, 0.5)


func _generate_passengers(spawn_chance: float) -> void:
	var landmarks: Dictionary = _city_map.landmark_nodes
	var names: Array = landmarks.keys()
	if names.size() < 2:
		return
	for n_var in names:
		if randf() >= spawn_chance:
			continue
		var origin_name: String = str(n_var)
		var dest_candidates: Array[String] = []
		for d_var in names:
			var d_name: String = str(d_var)
			if d_name != origin_name:
				dest_candidates.append(d_name)
		var dest_name: String = dest_candidates[randi() % dest_candidates.size()]
		var p: Passenger = PASSENGER_SCENE.instantiate() as Passenger
		var genres: Array[String] = _radio.get_playable_genres()
		p.setup(landmarks[origin_name] as Vector2, dest_name, landmarks[dest_name] as Vector2, "", "", genres)
		_city_map.get_entities_root().add_child(p)
		waiting_passengers.append(p)


func _create_tutorial_passengers() -> void:
	var lm: Dictionary = _city_map.landmark_nodes
	if lm.has("City Entrance") and lm.has("Cornered C.O"):
		var p1: Passenger = PASSENGER_SCENE.instantiate() as Passenger
		p1.setup(lm["City Entrance"] as Vector2, "Cornered C.O", lm["Cornered C.O"] as Vector2, "pedestrian_1", "pop")
		_city_map.get_entities_root().add_child(p1)
		waiting_passengers.append(p1)
	if lm.has("Long Avenue") and lm.has("City Endhole"):
		var p2: Passenger = PASSENGER_SCENE.instantiate() as Passenger
		p2.setup(lm["Long Avenue"] as Vector2, "City Endhole", lm["City Endhole"] as Vector2, "pedestrian_2", "rock")
		_city_map.get_entities_root().add_child(p2)
		waiting_passengers.append(p2)


func _check_tutorial_triggers() -> void:
	var taxi_rect: Rect2 = Rect2(taxi.global_position - Vector2(10.0, 10.0), Vector2(20.0, 20.0))
	for i in _tutorial_triggers.size():
		var trig: Dictionary = _tutorial_triggers[i]
		var rect: Rect2 = trig["rect"] as Rect2
		if not rect.intersects(taxi_rect):
			continue

		var cond: String = str(trig.get("condition", ""))
		if _evaluate_tutorial_condition(cond):
			_tutorial_triggers.remove_at(i)
			_last_checkpoint = taxi.global_position
			taxi.stop_immediately()
			var raw_msg: String = I18n.t(str(trig["message"]))
			var formatted: String = raw_msg.format(taxi.get_binding_texts())
			_show_tutorial_dialog(I18n.t("tutorial_title"), formatted)
		else:
			_tutorial_paused = true
			taxi.stop_immediately()
			AudioManager.play_sfx("crash_car")
			var tween: Tween = create_tween()
			tween.tween_property(_intro_fade, "color:a", 1.0, 0.4)
			tween.tween_callback(func() -> void:
				taxi.global_position = _last_checkpoint
				_camera.snap_to(taxi.global_position)
			)
			tween.tween_property(_intro_fade, "color:a", 0.0, 0.4)
			tween.tween_callback(func() -> void:
				_tutorial_paused = false
			)
		break


func _evaluate_tutorial_condition(cond: String) -> bool:
	match cond:
		"":
			return true
		"is_vibe":
			return taxi.is_vibe_mode()
		"has_delivered_a_passenger":
			return rule_strategy is TutorialStrategy and (rule_strategy as TutorialStrategy).passengers_delivered > 0
		"has_passenger":
			return active_passenger != null and active_passenger.is_riding()
		_:
			return true


func _check_tutorial_completion() -> void:
	if _tutorial_completed:
		return
	var delivered: int = (rule_strategy as TutorialStrategy).passengers_delivered if rule_strategy is TutorialStrategy else 0
	if delivered >= 2 and active_passenger == null:
		_tutorial_completed = true
		taxi.stop_immediately()
		_show_tutorial_dialog(
			I18n.t("tutorial_completed_title"),
			I18n.t("tutorial_completed_msg"),
			func() -> void:
				AudioManager.stop_gameplay_audio()
				GameFlow.change_scene("res://src/menus/title_screen.tscn", 0.5, 0.5)
		)


func _show_tutorial_dialog(title_str: String, msg_str: String, on_close: Callable = Callable()) -> void:
	taxi.reset_inputs()
	var mb_scene: PackedScene = load("res://src/menus/message_box.tscn") as PackedScene
	var mb: MessageBoxModal = mb_scene.instantiate() as MessageBoxModal
	mb.setup(title_str, msg_str)
	if on_close.is_valid():
		mb.closed.connect(on_close)
	GameFlow.push_modal(mb, true)


func _trigger_end_of_run() -> void:
	_game_over_triggered = true
	taxi.stop_immediately()
	AudioManager.stop_gameplay_audio()

	var result: Dictionary = rule_strategy.evaluate_end(taxi.health)
	if str(result.get("action", "game_over")) == "end_of_day":
		var eod_scene: PackedScene = load("res://src/menus/end_of_day.tscn") as PackedScene
		var eod: EndOfDayModal = eod_scene.instantiate() as EndOfDayModal
		eod.setup(result)
		GameFlow.push_modal(eod, true)
	else:
		var go_scene: PackedScene = load("res://src/menus/game_over.tscn") as PackedScene
		var go: GameOverModal = go_scene.instantiate() as GameOverModal
		go.setup(result)
		GameFlow.push_modal(go, true)
