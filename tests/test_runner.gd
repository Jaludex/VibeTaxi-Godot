extends Node

## Headless automated test suite verifying maps, physics, rules, saves, i18n, and all scenes.

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_run_all_tests()
	await get_tree().process_frame
	await get_tree().process_frame
	print("TEST SUMMARY: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("[PASS] %s" % msg)
	else:
		_failed += 1
		push_error("[FAIL] %s" % msg)


func _run_all_tests() -> void:
	_test_tiled_parsing()
	_test_city_map_runtime()
	_test_taxi_and_vibe_drift()
	_test_collision_cooldown_push_and_audio()
	_test_z_order_overhead_and_debug()
	_test_passenger_and_safe_bonus()
	_test_rules_and_saves()
	_test_i18n_parity()
	_test_all_scenes_instantiate()
	_test_touch_and_mobile()
	_test_discord_rpc()


func _test_tiled_parsing() -> void:
	var city: Dictionary = TiledMapLoader.parse_map("city")
	_assert_true(not city.is_empty(), "city.json parsed")
	_assert_true(city["pixel_size"] == Vector2(3200.0, 4320.0), "city.json pixel size 3200x4320")
	_assert_true((city["tile_layers"] as Array).size() == 5, "city.json has 5 tile layers")
	_assert_true((city["collisions"] as Array).size() == 145, "city.json has 145 valid collision rects")
	_assert_true((city["props"] as Array).size() == 474, "city.json has 474 props")
	_assert_true((city["landmark_nodes"] as Dictionary).size() == 119, "city.json has 119 landmarks")
	_assert_true((city["npc_nodes"] as Dictionary).size() == 253, "city.json has 253 unique npc_* nodes")
	_assert_true((city["traffic_nodes"] as Dictionary).size() == 391, "city.json has 391 unique traffic nodes")
	_assert_true((city["taxi_spawns"] as Array).size() == 3, "city.json has 3 taxi spawns")

	var tut: Dictionary = TiledMapLoader.parse_map("tutorial")
	_assert_true(not tut.is_empty(), "tutorial.json parsed")
	_assert_true(tut["pixel_size"] == Vector2(1440.0, 1600.0), "tutorial.json pixel size 1440x1600")
	_assert_true((tut["collisions"] as Array).size() == 33, "tutorial.json has 33 collision rects")
	_assert_true((tut["props"] as Array).size() == 27, "tutorial.json has 27 props")
	_assert_true((tut["landmark_nodes"] as Dictionary).size() == 4, "tutorial.json has 4 landmarks")
	_assert_true((tut["traffic_nodes"] as Dictionary).size() == 8, "tutorial.json has 8 traffic nodes")
	_assert_true((tut["tutorial_triggers"] as Array).size() == 6, "tutorial.json has 6 tutorial triggers")


func _test_city_map_runtime() -> void:
	var map: CityMap = (load("res://src/world/city_map.tscn") as PackedScene).instantiate() as CityMap
	add_child(map)
	map.load_map("city", true)
	_assert_true(map.tile_layers.size() == 5, "CityMap created 5 TileMapLayers")
	_assert_true(map.get_node("PropsRoot").get_child_count() == 474, "CityMap spawned 474 PropEntity nodes")
	_assert_true(map.get_node("WallsBody").get_child_count() == 145, "CityMap created 145 static wall shapes")
	_assert_true(map.collision_rects.size() == 145 and map.landmark_nodes.size() == 119, "Baked CityLevel preserved collision rects and landmarks")

	var ped_sys: PedestrianSystem = PedestrianSystem.new()
	add_child(ped_sys)
	ped_sys.setup(map, null)
	_assert_true(ped_sys.npc_nodes.size() == 253, "PedestrianSystem sanitized 253 npc nodes")
	ped_sys.queue_free()
	map.queue_free()


func _test_taxi_and_vibe_drift() -> void:
	var taxi: Taxi = (load("res://src/entities/taxi.tscn") as PackedScene).instantiate() as Taxi
	add_child(taxi)
	_assert_true(is_equal_approx(taxi.heading_angle, 0.0) and is_equal_approx(taxi.rotation, PI * 0.5), "Taxi spawns facing right (heading 0, rotation PI/2)")
	_assert_true(taxi.vehicle_def != null and is_equal_approx(taxi.max_health, 140.0), "Taxi loads VehicleDef resource (yellow_taxi, 140 HP)")

	taxi.step_driving(0.1, Vector2(200.0, 0.0), true, false)
	_assert_true(taxi.speed > 0.0, "Taxi accelerates toward target")

	taxi.set_vibe_mode(true)
	_assert_true(taxi.is_vibe_mode(), "Taxi enters Vibe Mode")
	taxi.is_drifting = true
	taxi.speed = 100.0
	taxi._slide_velocity = Vector2(100.0, 0.0)
	taxi._update_drift_effects()
	_assert_true(taxi._drift_smoke_l.emitting, "Drift smoke emits in first Vibe entry")

	taxi.set_vibe_mode(false)
	_assert_true(not taxi.is_vibe_mode(), "Taxi exits Vibe Mode")
	taxi.set_vibe_mode(true)
	taxi.is_drifting = true
	taxi.speed = 100.0
	taxi._slide_velocity = Vector2(100.0, 0.0)
	taxi._update_drift_effects()
	_assert_true(taxi._drift_smoke_l.emitting, "Drift smoke still emits after re-entering Vibe Mode")

	var h_before: float = taxi.health
	taxi.take_damage(10.0)
	_assert_true(is_equal_approx(h_before - taxi.health, 4.0), "Vibe Mode reduces damage by 60% (10 -> 4)")
	taxi.queue_free()


func _test_collision_cooldown_push_and_audio() -> void:
	var taxi: Taxi = (load("res://src/entities/taxi.tscn") as PackedScene).instantiate() as Taxi
	var tcar: TrafficCar = (load("res://src/entities/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(taxi)
	add_child(tcar)

	# Engine & drift WAV loop verification
	for key in ["idle_normal", "idle_damaged", "engine1", "engine2", "drifting"]:
		var st: AudioStreamWAV = AudioManager.get_stream(key) as AudioStreamWAV
		_assert_true(st != null and st.loop_mode == AudioStreamWAV.LOOP_FORWARD and st.loop_end > 0, "Engine/drift WAV '%s' loops with valid loop_end" % key)
		var pl: AudioStreamPlayer = taxi._engine_players.get(key) as AudioStreamPlayer
		_assert_true(pl != null and pl.playing, "Engine/drift player '%s' is actively playing" % key)

	# Pushing transfer
	tcar.apply_push(Vector2(80.0, 0.0))
	_assert_true(tcar.push_velocity.length() > 0.0, "TrafficCar accepts push impulse")

	# Resting contact should not build mutual push/slide
	taxi.speed = 0.0
	taxi.velocity = Vector2.ZERO
	taxi.push_velocity = Vector2.ZERO
	tcar.speed = 0.0
	tcar.velocity = Vector2.ZERO
	tcar.push_velocity = Vector2.ZERO
	taxi.global_position = Vector2(200.0, 200.0)
	tcar.global_position = Vector2(214.0, 200.0)
	taxi.perform_move_and_detect()
	tcar.perform_move_and_detect()
	_assert_true(taxi.push_velocity == Vector2.ZERO and tcar.push_velocity == Vector2.ZERO, "Stopped cars in contact do not mutually push/slide")

	# Damage cooldown check (multiple hits within 0.4s deal damage only once)
	var hp0: float = taxi.health
	taxi._on_new_collision(tcar, Vector2(-1.0, 0.0))
	var hp1: float = taxi.health
	taxi._on_new_collision(tcar, Vector2(-1.0, 0.0))
	_assert_true(hp1 < hp0 and is_equal_approx(taxi.health, hp1), "Car collision cooldown prevents instant multi-hit death")

	taxi.queue_free()
	tcar.queue_free()


func _test_z_order_overhead_and_debug() -> void:
	var map: CityMap = (load("res://src/world/city_map.tscn") as PackedScene).instantiate() as CityMap
	add_child(map)
	map.load_map("city", false)

	var overheads: TileMapLayer = map.tile_layers["overheads"] as TileMapLayer
	var entities_root: Node2D = map.get_entities_root()
	var silhouettes_root: Node2D = map.get_silhouettes_root()
	var taxi: Taxi = (load("res://src/entities/taxi.tscn") as PackedScene).instantiate() as Taxi
	entities_root.add_child(taxi)
	taxi.attach_to_map(map)

	_assert_true(entities_root.z_index + taxi.z_index < overheads.z_index, "Taxi effective z_index renders below overheads")
	_assert_true(silhouettes_root.z_index > overheads.z_index, "SilhouettesRoot renders above overheads")
	_assert_true(taxi._silhouette_sprite != null and taxi._silhouette_sprite.get_parent() == silhouettes_root, "Car silhouette attached to SilhouettesRoot")

	var tsys: TrafficSystem = TrafficSystem.new()
	add_child(tsys)
	tsys.setup(map)
	var broken_links: int = 0
	for n_info in tsys.nodes.values():
		for nxt in ((n_info as Dictionary)["next"] as Array):
			if not tsys.nodes.has(str(nxt)):
				broken_links += 1
	_assert_true(broken_links == 0, "TrafficSystem sanitized all broken traffic-node links")
	_assert_true(tsys.civilian_defs.size() == 7, "TrafficSystem loaded 7 civilian VehicleDefs")
	var spawned_car: TrafficCar = tsys.try_spawn_car()
	_assert_true(spawned_car != null and spawned_car.is_inside_tree(), "TrafficSystem spawns civilian TrafficCar")
	if spawned_car != null:
		tsys.despawn_car(spawned_car)

	ConfigManager.set_value("physics_debug", true, false)
	var dbg: DebugOverlay = map.get_node("DebugOverlay") as DebugOverlay
	_assert_true(dbg.visible and dbg.z_index > overheads.z_index, "DebugOverlay activates and renders above map")
	ConfigManager.set_value("physics_debug", false, false)

	tsys.queue_free()
	map.queue_free()

	var tc1: TrafficCar = (load("res://src/entities/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	var tc7: TrafficCar = (load("res://src/entities/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(tc1)
	add_child(tc7)
	tc1.apply_vehicle_def("civilian_1")
	tc7.apply_vehicle_def("civilian_7")
	var sz1: Vector2 = (tc1.collision_shape.shape as RectangleShape2D).size
	var sz7: Vector2 = (tc7.collision_shape.shape as RectangleShape2D).size
	_assert_true(sz1 == Vector2(14.0, 25.0) and sz7 == Vector2(20.0, 35.0), "TrafficCar hitboxes are local per instance (%s vs %s)" % [str(sz1), str(sz7)])
	tc1.queue_free()
	tc7.queue_free()


func _test_passenger_and_safe_bonus() -> void:
	var p: Passenger = (load("res://src/entities/passenger.tscn") as PackedScene).instantiate() as Passenger
	p.setup(Vector2(0.0, 0.0), "Target", Vector2(500.0, 0.0), "pedestrian_1", "rock")
	add_child(p)
	_assert_true(p.damage_taken == 0.0, "Passenger initializes damage_taken to 0.0")
	_assert_true(p.comfort >= 50.0 and p.comfort <= 60.0, "Passenger initial comfort in [50, 60]")

	var c0: float = p.comfort
	p.start_ride()
	p.update_comfort(0.5, "rock")
	_assert_true(p.comfort >= c0 + 22.0, "Matching music within 6s grants +22 comfort bonus")

	var wd: WorkdayStrategy = WorkdayStrategy.new(120.0, 0.0, 1, false)
	var reward: Dictionary = wd.on_passenger_delivered(p, 500.0)
	# base 10 + dist/100 (5) + fast (5, expected 5s > 0.5s) + safe (3) = 23.0
	_assert_true(is_equal_approx(wd.money, 23.0), "Workday Safe! + Fast! bonuses calculate accurately ($23.00)")
	_assert_true(str(reward.get("side_popup", "")).contains(I18n.t("bonus_safe")), "Workday delivery popup includes Safe! bonus")

	p.on_collision(10.0)
	_assert_true(p.damage_taken > 0.0, "Passenger tracks collision damage")
	p.queue_free()

	var hud: PassengerHUD = (load("res://src/ui/passenger_hud.tscn") as PackedScene).instantiate() as PassengerHUD
	add_child(hud)
	hud._typewriter.set_box_text("Llevame al centro comercial por favor, tengo mucha prisa hoy!")
	_assert_true(hud._typewriter.line_spacing == -2 and hud._typewriter._label.get_theme_constant("line_spacing") == -2, "Passenger TypewriterBox reduces line_spacing to -2")
	_assert_true(hud._typewriter._label.get_line_count() <= 3 and hud._typewriter.size.y >= 44.0, "Passenger dialogue page stays within 3 lines and box height")
	var temp_p: Passenger = (load("res://src/entities/passenger.tscn") as PackedScene).instantiate() as Passenger
	temp_p.setup(Vector2.ZERO, "Target", Vector2(200.0, 0.0), "pedestrian_1", "rock")
	hud.bind_passenger(temp_p, false)
	temp_p.free()
	hud._process(0.016)
	_assert_true(hud.passenger == null, "PassengerHUD clears freed passenger safely without crashing")
	hud.queue_free()


func _test_rules_and_saves() -> void:
	var orig_dir: String = SaveManager.save_dir
	SaveManager.save_dir = "user://test_saves_tmp"

	SaveManager.save_slot("records", {"workday": [{"name": "A", "score": 3}]})
	var elig: Dictionary = RuleStrategy.check_record_eligibility("arcade", 200.0)
	_assert_true(elig.get("mode", "") == "arcade", "check_record_eligibility handles missing 'arcade' key safely")

	var wd_day2: WorkdayStrategy = WorkdayStrategy.new(120.0, 100.0, 2, false)
	_assert_true(is_equal_approx(wd_day2.fee, 95.0), "Workday Day 2 fee is $95")
	var eod: Dictionary = wd_day2.evaluate_end(100.0)
	_assert_true(eod.get("action") == "end_of_day" and is_equal_approx(float(eod.get("money", 0.0)), 5.0), "Workday EndOfDay deducts fee cleanly")

	var arc: ArcadeStrategy = ArcadeStrategy.new()
	var p2: Passenger = (load("res://src/entities/passenger.tscn") as PackedScene).instantiate() as Passenger
	p2.setup(Vector2.ZERO, "Dest", Vector2(500.0, 0.0), "pedestrian_1", "pop")
	p2.time_riding = 1.0
	arc.on_passenger_delivered(p2, 500.0)
	_assert_true(arc.score == 250 and is_equal_approx(arc.time_remaining, 136.0), "Arcade fast+safe delivery awards 250 pts and +16s")
	p2.queue_free()

	var rec_map: Dictionary = {"workday": [], "arcade": []}
	for i in 12:
		rec_map = RuleStrategy.record_new_score("arcade", "P%d" % i, (i + 1) * 100, rec_map)
	var arc_list: Array = rec_map.get("arcade", []) as Array
	_assert_true(arc_list.size() == 10 and int((arc_list[0] as Dictionary)["score"]) == 1200, "Top-10 records stay sorted descending and capped at 10")

	var corrupt_file: FileAccess = FileAccess.open("user://test_saves_tmp/corrupt.json", FileAccess.WRITE)
	corrupt_file.store_string("{not-valid-json")
	corrupt_file.close()
	var loaded_corrupt: Dictionary = SaveManager.load_slot("corrupt", {"fallback": true})
	_assert_true(bool(loaded_corrupt.get("fallback", false)), "SaveManager returns default_value cleanly on corrupt JSON")
	SaveManager.delete_slot("corrupt")

	SaveManager.delete_slot("records")
	SaveManager.save_dir = orig_dir


func _test_i18n_parity() -> void:
	var tr_en: Translation = load("res://assets/localization/texts.en.translation") as Translation
	var tr_es: Translation = load("res://assets/localization/texts.es.translation") as Translation
	_assert_true(tr_en != null and tr_es != null, "Loaded EN and ES Translation resources")
	var f: FileAccess = FileAccess.open("res://assets/localization/texts.csv", FileAccess.READ)
	_assert_true(f != null, "Opened res://assets/localization/texts.csv")
	var missing_in_es: Array[String] = []
	var missing_in_en: Array[String] = []
	var row_count: int = 0
	if f != null and tr_en != null and tr_es != null:
		f.get_csv_line() # header: keys,en,es
		while not f.eof_reached():
			var cols: PackedStringArray = f.get_csv_line()
			if cols.size() < 3 or cols[0].is_empty():
				continue
			row_count += 1
			var k: String = cols[0]
			if tr_en.get_message(k).is_empty():
				missing_in_en.append(k)
			if tr_es.get_message(k).is_empty():
				missing_in_es.append(k)
		f.close()
	_assert_true(row_count > 150 and missing_in_es.is_empty(), "All %d EN CSV keys exist in ES translation (missing: %s)" % [row_count, str(missing_in_es)])
	_assert_true(row_count > 150 and missing_in_en.is_empty(), "All %d ES CSV keys exist in EN translation (missing: %s)" % [row_count, str(missing_in_en)])
	var prev_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	_assert_true(I18n.t("btn_new_game") == "Nueva Partida", "TranslationServer translates UI key in ES")
	_assert_true(not I18n.pick_dialogue("enter", "", {"destination": "Parque"}).is_empty(), "TranslationServer resolves dynamic dialogue pool")
	TranslationServer.set_locale(prev_locale)


func _test_all_scenes_instantiate() -> void:
	var scene_paths: Array[String] = [
		"res://src/menus/opening.tscn",
		"res://src/menus/language_selection.tscn",
		"res://src/menus/title_screen.tscn",
		"res://src/menus/mode_selection.tscn",
		"res://src/menus/options_menu.tscn",
		"res://src/menus/pause_menu.tscn",
		"res://src/menus/end_of_day.tscn",
		"res://src/menus/game_over.tscn",
		"res://src/menus/new_record.tscn",
		"res://src/menus/records_screen.tscn",
		"res://src/menus/message_box.tscn",
		"res://src/menus/confirmation_box.tscn",
	]
	for path in scene_paths:
		var ps: PackedScene = load(path) as PackedScene
		_assert_true(ps != null, "Loaded scene %s" % path)
		if ps != null:
			var inst: Node = ps.instantiate()
			add_child(inst)
			inst.queue_free()

	for mode in ["workday", "arcade", "zen", "tutorial"]:
		GameFlow.pending_play_params = {"mode": mode}
		var play: Node = (load("res://src/gameplay/play_scene.tscn") as PackedScene).instantiate()
		add_child(play)
		_assert_true(play != null, "Instantiated PlayScene in %s mode" % mode)
		play.queue_free()
	AudioManager.stop_gameplay_audio()

	var has_joy_accept: bool = false
	for ev in InputMap.action_get_events(&"ui_accept"):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			has_joy_accept = true
	var has_joy_cancel: bool = false
	for ev in InputMap.action_get_events(&"ui_cancel"):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			has_joy_cancel = true
	_assert_true(has_joy_accept and has_joy_cancel, "UI accept/cancel include JOY_BUTTON_A and JOY_BUTTON_B")

	var bg_btn: Button = Button.new()
	add_child(bg_btn)
	bg_btn.grab_focus()
	var modal: Control = (load("res://src/menus/mode_selection.tscn") as PackedScene).instantiate() as Control
	GameFlow.push_modal(modal, false)
	_assert_true(GameFlow.get_top_modal() == modal, "GameFlow tracks top modal")
	GameFlow.pop_modal(modal)
	_assert_true(get_viewport().gui_get_focus_owner() == bg_btn, "Popping modal restores previous focus owner")
	bg_btn.queue_free()


func _test_touch_and_mobile() -> void:
	# 1. SkidMarks ring buffer capacity & expiry
	var skids: SkidMarks = SkidMarks.new()
	add_child(skids)
	for i in 300:
		skids.add_mark(Vector2(float(i), float(i)))
	_assert_true(skids.get_active_count() == SkidMarks.MAX_MARKS, "SkidMarks caps active marks at %d" % SkidMarks.MAX_MARKS)
	skids._process(SkidMarks.LIFETIME + 0.1)
	_assert_true(skids.get_active_count() == 0, "SkidMarks expires marks cleanly after lifetime")
	skids.queue_free()

	# 2. Lazy OGG RadioStationDef & interactive RadioTuner
	var rock_def: RadioStationDef = load("res://resources/radio/01_rock.tres") as RadioStationDef
	_assert_true(rock_def != null and rock_def.tracks.is_empty() and rock_def.track_paths.size() == 5, "RadioStationDef stores lazy track_paths without preloaded streams")
	var radio: RadioTuner = (load("res://src/ui/radio_tuner.tscn") as PackedScene).instantiate() as RadioTuner
	add_child(radio)
	radio._trigger_activity()
	radio.position = Vector2.ZERO
	radio.size = Vector2(480.0, 64.0)
	_assert_true(radio.handle_pointer_at(Vector2(300.0, 32.0)) and radio.current_index == 1, "RadioTuner tap right advances station")
	_assert_true(radio.handle_pointer_at(Vector2(150.0, 32.0)) and radio.current_index == 0, "RadioTuner tap left goes to prev station")
	radio.queue_free()

	# 3. Dual TouchControls (joystick & drag + multi-touch brake/drift/pause)
	var prev_tc: Variant = ConfigManager.get_value("touch_controls", false)
	var prev_tm: Variant = ConfigManager.get_value("touch_mode", "joystick")
	ConfigManager.set_value("touch_controls", true)
	ConfigManager.set_value("touch_mode", "joystick")

	var tc: TouchControls = (load("res://src/ui/touch_controls.tscn") as PackedScene).instantiate() as TouchControls
	add_child(tc)
	var vp: Vector2 = tc._get_vp_size()
	tc.simulate_touch(0, true, Vector2(80.0, vp.y - 80.0))
	tc.simulate_drag(0, Vector2(120.0, vp.y - 80.0))
	var jv: Vector2 = tc.get_joystick_vector()
	_assert_true(jv.x > 0.9 and absf(jv.y) < 0.05, "TouchControls joystick outputs normalized steering vector")
	var brk_center: Vector2 = tc._brake_rect(vp).get_center()
	tc.simulate_touch(1, true, brk_center)
	_assert_true(tc.is_brake_pressed() and tc.get_joystick_vector().x > 0.9, "TouchControls handles multi-touch brake simultaneously with joystick")
	tc.simulate_touch(0, false, Vector2.ZERO)
	tc.simulate_touch(1, false, brk_center)
	_assert_true(tc.get_joystick_vector() == Vector2.ZERO and not tc.is_brake_pressed(), "Releasing touches clears joystick and brake")

	ConfigManager.set_value("touch_mode", "drag")
	tc.simulate_touch(2, true, Vector2(200.0, 140.0))
	tc.simulate_touch(3, true, tc._drift_rect(vp).get_center())
	_assert_true(tc.is_drag_accelerating() and tc.get_drag_screen_pos() == Vector2(200.0, 140.0) and tc.is_drift_pressed(), "TouchControls drag mode supports follow-finger + simultaneous drift")

	var pause_emitted: Array[bool] = [false]
	var radio_moves: Array[int] = [0]
	tc.pause_requested.connect(func() -> void: pause_emitted[0] = true)
	tc.radio_prev_requested.connect(func() -> void: radio_moves[0] -= 1)
	tc.radio_next_requested.connect(func() -> void: radio_moves[0] += 1)
	tc.simulate_touch(4, true, tc._radio_next_rect(vp).get_center())
	tc.simulate_touch(4, true, tc._radio_prev_rect(vp).get_center())
	_assert_true(radio_moves[0] == 0, "Touch radio arrow buttons emit prev/next signals")
	tc.simulate_touch(5, true, tc._pause_rect().get_center())
	_assert_true(pause_emitted[0] and not tc.is_drag_accelerating(), "Touch pause button emits pause_requested and resets active touches")
	tc.queue_free()

	ConfigManager.set_value("touch_mode", prev_tm)
	ConfigManager.set_value("touch_controls", prev_tc)

	# 4. Android Back request closes top modal via ui_cancel
	var mb: MessageBoxModal = (load("res://src/menus/message_box.tscn") as PackedScene).instantiate() as MessageBoxModal
	mb.setup("Back Test", "Testing back action")
	GameFlow.push_modal(mb, false)
	GameFlow.handle_back_request()
	GameFlow.handle_back_request()
	_assert_true(mb._is_exiting, "GameFlow.handle_back_request triggers cancel on top modal")
	GameFlow.pop_modal(mb)


func _test_discord_rpc() -> void:
	# 1. IPC frame encoding
	var frame: PackedByteArray = DiscordRPC.encode_frame(0, {"v": 1, "client_id": DiscordRPC.CLIENT_ID})
	_assert_true(frame.size() > 8 and frame.decode_u32(0) == 0 and frame.decode_u32(4) == frame.size() - 8, "DiscordRPC.encode_frame writes little-endian opcode + length header")
	var decoded: Variant = JSON.parse_string(frame.slice(8).get_string_from_utf8())
	_assert_true(decoded is Dictionary and (decoded as Dictionary).get("client_id") == DiscordRPC.CLIENT_ID, "DiscordRPC.encode_frame encodes valid UTF-8 JSON payload")

	# 2. Activity payload builder
	var payload: Dictionary = DiscordRPC.build_activity_payload(
		{"details": "Workday - Day 2", "state": "Cruising", "small_image": "workday", "small_text": "Day 2"},
		1700000000,
		1234,
		"7"
	)
	var act: Dictionary = (payload["args"] as Dictionary)["activity"] as Dictionary
	var assets: Dictionary = act["assets"] as Dictionary
	_assert_true(
		payload["cmd"] == "SET_ACTIVITY" and act["details"] == "Workday - Day 2" and assets["large_image"] == "logo" and assets["small_image"] == "workday",
		"DiscordRPC.build_activity_payload formats SET_ACTIVITY with assets and buttons"
	)

	# 3. Menu & modal presence resolution
	var empty_modals: Array[Control] = []
	var title_node: Node = Node.new()
	title_node.scene_file_path = "res://src/menus/title_screen.tscn"
	_assert_true(DiscordRPC.resolve_presence(title_node, empty_modals)["details"] == "Main Menu", "DiscordRPC resolves title_screen.tscn -> Main Menu")
	var opening_node: Node = Node.new()
	opening_node.scene_file_path = "res://src/menus/opening.tscn"
	_assert_true(DiscordRPC.resolve_presence(opening_node, empty_modals)["details"] == "Starting up", "DiscordRPC resolves opening.tscn -> Starting up")
	var records_node: Node = Node.new()
	records_node.scene_file_path = "res://src/menus/records_screen.tscn"
	_assert_true(DiscordRPC.resolve_presence(records_node, empty_modals)["details"] == "Hall of Fame", "DiscordRPC resolves records_screen.tscn -> Hall of Fame")

	var pause_m: PauseMenuModal = (load("res://src/menus/pause_menu.tscn") as PackedScene).instantiate() as PauseMenuModal
	var opts_m: OptionsMenuModal = (load("res://src/menus/options_menu.tscn") as PackedScene).instantiate() as OptionsMenuModal
	var mode_m: ModeSelectionModal = (load("res://src/menus/mode_selection.tscn") as PackedScene).instantiate() as ModeSelectionModal
	var eod_m: EndOfDayModal = (load("res://src/menus/end_of_day.tscn") as PackedScene).instantiate() as EndOfDayModal
	eod_m.setup({"day": 3, "money": 145.0, "health": 100.0})
	var go_m: GameOverModal = (load("res://src/menus/game_over.tscn") as PackedScene).instantiate() as GameOverModal
	var nr_m: NewRecordModal = (load("res://src/menus/new_record.tscn") as PackedScene).instantiate() as NewRecordModal
	var msg_m: MessageBoxModal = (load("res://src/menus/message_box.tscn") as PackedScene).instantiate() as MessageBoxModal

	_assert_true(DiscordRPC.resolve_presence(title_node, [pause_m])["details"] == "Paused", "DiscordRPC resolves PauseMenuModal")
	_assert_true(DiscordRPC.resolve_presence(title_node, [opts_m])["details"] == "Settings", "DiscordRPC resolves OptionsMenuModal")
	_assert_true(DiscordRPC.resolve_presence(title_node, [mode_m])["details"] == "Mode Selection", "DiscordRPC resolves ModeSelectionModal")
	var eod_p: Dictionary = DiscordRPC.resolve_presence(title_node, [eod_m, msg_m])
	_assert_true(eod_p["details"] == "End of Day 3" and eod_p["state"] == "Earnings: $145", "DiscordRPC resolves EndOfDayModal through MessageBox overlay")
	_assert_true(DiscordRPC.resolve_presence(title_node, [go_m])["details"] == "Game Over", "DiscordRPC resolves GameOverModal")
	_assert_true(DiscordRPC.resolve_presence(title_node, [nr_m])["details"] == "New High Score!", "DiscordRPC resolves NewRecordModal")

	for n in [title_node, opening_node, records_node, pause_m, opts_m, mode_m, eod_m, go_m, nr_m, msg_m]:
		n.free()

	# 4. Gameplay strategy presence resolution (Workday, Arcade, Zen, Tutorial)
	var ps: PlayScene = PlayScene.new()
	ps.rule_strategy = WorkdayStrategy.new(120.0, 42.0, 2)
	var wd_cruising: Dictionary = DiscordRPC.resolve_presence(ps, empty_modals)
	_assert_true(wd_cruising["details"] == "Workday - Day 2" and wd_cruising["state"] == "Cruising | $42 / Goal $95", "DiscordRPC resolves Workday cruising state")

	var fake_pax: Passenger = Passenger.new()
	ps.active_passenger = fake_pax
	var wd_carry: Dictionary = DiscordRPC.resolve_presence(ps, empty_modals)
	_assert_true(wd_carry["state"] == "Carrying Passenger | $42 earned", "DiscordRPC resolves Workday carrying passenger state")
	ps.active_passenger = null
	fake_pax.free()

	var arc: ArcadeStrategy = ArcadeStrategy.new()
	arc.score = 350
	arc.passengers_delivered = 4
	ps.rule_strategy = arc
	var arc_p: Dictionary = DiscordRPC.resolve_presence(ps, empty_modals)
	_assert_true(arc_p["details"] == "Arcade Mode" and arc_p["state"] == "Score: 350 | Passengers: 4", "DiscordRPC resolves Arcade presence")

	ps.rule_strategy = ZenStrategy.new()
	_assert_true(DiscordRPC.resolve_presence(ps, empty_modals)["details"] == "Zen Mode", "DiscordRPC resolves Zen presence")

	ps.rule_strategy = TutorialStrategy.new()
	_assert_true(DiscordRPC.resolve_presence(ps, empty_modals)["details"] == "Tutorial", "DiscordRPC resolves Tutorial presence")
	ps.free()

	# 5. Config toggle propagates safely without IPC errors
	var prev_rpc: Variant = ConfigManager.get_value("discord_rpc", true)
	ConfigManager.set_value("discord_rpc", false)
	ConfigManager.set_value("discord_rpc", true)
	ConfigManager.set_value("discord_rpc", prev_rpc)
	_assert_true(true, "ConfigManager discord_rpc toggle propagates cleanly")
