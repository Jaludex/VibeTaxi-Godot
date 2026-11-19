class_name TrafficSystem
extends Node

## Manages sanitized traffic node graph, off-screen spawning, and off-screen despawning.

const TRAFFIC_CAR_SCENE: PackedScene = preload("res://src/entities/traffic_car.tscn")

@export var civilian_defs: Array[VehicleDef] = []

var city_map: CityMap = null
var nodes: Dictionary = {}
var active_cars: Array[TrafficCar] = []
var camera_ref: Camera2D = null

var _spawn_timer: float = 0.0


func setup(p_city_map: CityMap) -> void:
	city_map = p_city_map
	_sanitize_nodes(city_map.traffic_nodes)
	if civilian_defs.is_empty():
		_load_default_civilian_defs()


func _load_default_civilian_defs() -> void:
	var files: PackedStringArray = ResourceLoader.list_directory("res://resources/vehicles")
	if files.is_empty():
		var dir: DirAccess = DirAccess.open("res://resources/vehicles")
		if dir != null:
			files = dir.get_files()
	files.sort()
	for raw_name in files:
		var fname: String = raw_name.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		var res: VehicleDef = load("res://resources/vehicles/" + fname) as VehicleDef
		if res != null and res.id != "yellow_taxi" and not (res in civilian_defs):
			civilian_defs.append(res)


func _sanitize_nodes(raw_nodes: Dictionary) -> void:
	nodes.clear()
	for node_name_var in raw_nodes.keys():
		var name_str: String = str(node_name_var)
		nodes[name_str] = (raw_nodes[name_str] as Dictionary).duplicate(true)

	# Strip broken/typo references so cars don't hit phantom dead ends
	for node_name_var in nodes.keys():
		var info: Dictionary = nodes[str(node_name_var)] as Dictionary
		var valid_next: Array[String] = []
		for nxt_var in (info.get("next", []) as Array):
			var nxt: String = str(nxt_var)
			if nodes.has(nxt) and nxt != str(node_name_var):
				valid_next.append(nxt)
		info["next"] = valid_next


func _process(delta: float) -> void:
	if city_map == null or nodes.is_empty():
		return

	_prune_distant_cars()

	_spawn_timer += delta
	if _spawn_timer >= GameConstants.TRAFFIC_SPAWN_INTERVAL:
		_spawn_timer = 0.0
		if active_cars.size() < GameConstants.TRAFFIC_MAX_CARS:
			try_spawn_car()


func is_offscreen(world_pos: Vector2, extra_margin: float = 60.0) -> bool:
	if camera_ref == null:
		return true
	var cam_pos: Vector2 = camera_ref.get_screen_center_position()
	var vp_size: Vector2 = camera_ref.get_viewport_rect().size if camera_ref.is_inside_tree() else Vector2(GameConstants.VIRTUAL_WIDTH, GameConstants.VIRTUAL_HEIGHT)
	var margin_x: float = vp_size.x * 0.5 + extra_margin
	var margin_y: float = vp_size.y * 0.5 + extra_margin
	return absf(world_pos.x - cam_pos.x) > margin_x or absf(world_pos.y - cam_pos.y) > margin_y


func _prune_distant_cars() -> void:
	if camera_ref == null:
		return
	var cam_pos: Vector2 = camera_ref.get_screen_center_position()
	var despawn_sq: float = GameConstants.TRAFFIC_DESPAWN_DIST * GameConstants.TRAFFIC_DESPAWN_DIST
	for i in range(active_cars.size() - 1, -1, -1):
		var car: TrafficCar = active_cars[i]
		if not is_instance_valid(car):
			active_cars.remove_at(i)
			continue
		var dist_sq: float = car.global_position.distance_squared_to(cam_pos)
		if dist_sq > despawn_sq and is_offscreen(car.global_position, 40.0):
			despawn_car(car)


func get_node_position(node_name: String) -> Variant:
	if not nodes.has(node_name):
		return null
	return (nodes[node_name] as Dictionary)["pos"]


func get_node_next(node_name: String) -> String:
	if not nodes.has(node_name):
		return ""
	var next_list: Array = (nodes[node_name] as Dictionary).get("next", []) as Array
	if next_list.is_empty():
		return ""
	return str(next_list[randi() % next_list.size()])


func find_continuation_node(pos: Vector2, heading: float) -> String:
	var forward: Vector2 = Vector2(cos(heading), sin(heading))
	var best_name: String = ""
	var best_dist_sq: float = 220.0 * 220.0
	for node_name_var in nodes.keys():
		var node_name: String = str(node_name_var)
		var info: Dictionary = nodes[node_name] as Dictionary
		if (info["next"] as Array).is_empty():
			continue
		var n_pos: Vector2 = info["pos"] as Vector2
		var diff: Vector2 = n_pos - pos
		var d_sq: float = diff.length_squared()
		if d_sq < 400.0 or d_sq >= best_dist_sq:
			continue
		if diff.normalized().dot(forward) > 0.5:
			best_dist_sq = d_sq
			best_name = node_name
	return best_name


func try_spawn_car() -> TrafficCar:
	if civilian_defs.is_empty():
		return null

	var candidates: Array[String] = []
	var cam_pos: Vector2 = camera_ref.get_screen_center_position() if camera_ref != null else Vector2.ZERO
	var max_dist_sq: float = GameConstants.TRAFFIC_SPAWN_MAX_DIST * GameConstants.TRAFFIC_SPAWN_MAX_DIST

	for node_name_var in nodes.keys():
		var node_name: String = str(node_name_var)
		var info: Dictionary = nodes[node_name] as Dictionary
		if (info["next"] as Array).is_empty():
			continue
		var pos: Vector2 = info["pos"] as Vector2
		if camera_ref != null:
			if not is_offscreen(pos, 80.0):
				continue
			if pos.distance_squared_to(cam_pos) > max_dist_sq:
				continue
		candidates.append(node_name)

	if candidates.is_empty():
		return null

	var spawn_name: String = candidates[randi() % candidates.size()]
	var spawn_pos: Variant = get_node_position(spawn_name)
	var next_name: String = get_node_next(spawn_name)
	if spawn_pos == null or next_name.is_empty():
		return null
	var next_pos: Variant = get_node_position(next_name)
	if next_pos == null:
		return null

	var chosen_def: VehicleDef = civilian_defs[randi() % civilian_defs.size()]
	var car: TrafficCar = TRAFFIC_CAR_SCENE.instantiate() as TrafficCar
	city_map.get_entities_root().add_child(car)
	car.setup_traffic_def(chosen_def, spawn_pos as Vector2, next_pos as Vector2, get_node_next(next_name), self)
	active_cars.append(car)
	return car


func despawn_car(car: TrafficCar) -> void:
	active_cars.erase(car)
	if is_instance_valid(car):
		car.queue_free()
