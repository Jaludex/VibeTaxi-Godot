class_name PedestrianSystem
extends Node

## Manages sidewalk pedestrian NPCs, validating npc_* graph edges against buildings.

signal taxi_hit_pedestrian(taxi: Taxi)

const PEDESTRIAN_SCENE: PackedScene = preload("res://src/entities/pedestrian_npc.tscn")

var city_map: CityMap = null
var traffic_system: TrafficSystem = null
var camera_ref: Camera2D = null
var taxi_ref: Taxi = null

var npc_nodes: Dictionary = {}
var active_npcs: Array[PedestrianNPC] = []
var _spawn_timer: float = 0.0


func setup(p_city_map: CityMap, p_traffic_system: TrafficSystem = null) -> void:
	city_map = p_city_map
	traffic_system = p_traffic_system
	_sanitize_npc_nodes()


func _sanitize_npc_nodes() -> void:
	npc_nodes.clear()
	for node_name_var in city_map.npc_nodes.keys():
		var name_str: String = str(node_name_var)
		var info: Dictionary = (city_map.npc_nodes[name_str] as Dictionary).duplicate(true)
		npc_nodes[name_str] = info

	for name_var in npc_nodes.keys():
		var node_name: String = str(name_var)
		var data: Dictionary = npc_nodes[node_name] as Dictionary
		var p1: Vector2 = data["pos"] as Vector2
		var valid_next: Array[String] = []
		for n_var in (data["next"] as Array):
			var n: String = str(n_var)
			if n == node_name:
				continue
			if not npc_nodes.has(n) and not city_map.landmark_nodes.has(n):
				continue
			var p2: Vector2 = get_node_pos(n, p1)
			if p1.distance_squared_to(p2) > 360000.0: # 600^2
				continue
			if not city_map.line_intersects_building(p1, p2):
				valid_next.append(n)
		data["next"] = valid_next
		if valid_next.is_empty():
			data["despawn"] = true


func _process(delta: float) -> void:
	if city_map == null or npc_nodes.is_empty():
		return

	_prune_distant_npcs()

	_spawn_timer += delta
	if _spawn_timer >= GameConstants.PEDESTRIAN_SPAWN_INTERVAL:
		_spawn_timer = 0.0
		if randf() <= GameConstants.PEDESTRIAN_SPAWN_CHANCE and active_npcs.size() < GameConstants.PEDESTRIAN_MAX_COUNT:
			_try_spawn_npc()


func _prune_distant_npcs() -> void:
	if camera_ref == null:
		return
	var cam_pos: Vector2 = camera_ref.get_screen_center_position()
	var max_dist_sq: float = GameConstants.PEDESTRIAN_MAX_DISTANCE * GameConstants.PEDESTRIAN_MAX_DISTANCE
	for i in range(active_npcs.size() - 1, -1, -1):
		var npc: PedestrianNPC = active_npcs[i]
		if not is_instance_valid(npc) or npc.current_state == PedestrianNPC.State.DEAD:
			active_npcs.remove_at(i)
			continue
		if npc.global_position.distance_squared_to(cam_pos) > max_dist_sq:
			despawn_npc(npc)


func _try_spawn_npc() -> void:
	var candidates: Array[String] = []
	var cam_pos: Vector2 = camera_ref.get_screen_center_position() if camera_ref != null else Vector2.ZERO
	var vp_size: Vector2 = camera_ref.get_viewport_rect().size if (camera_ref != null and camera_ref.is_inside_tree()) else Vector2(GameConstants.VIRTUAL_WIDTH, GameConstants.VIRTUAL_HEIGHT)
	var margin_x: float = vp_size.x * 0.5 + 40.0
	var margin_y: float = vp_size.y * 0.5 + 40.0
	var range_sq: float = GameConstants.PEDESTRIAN_SPAWN_RANGE * GameConstants.PEDESTRIAN_SPAWN_RANGE

	for name_var in npc_nodes.keys():
		var n_name: String = str(name_var)
		var data: Dictionary = npc_nodes[n_name] as Dictionary
		if (data["next"] as Array).is_empty():
			continue
		var pos: Vector2 = data["pos"] as Vector2
		if camera_ref != null:
			if absf(pos.x - cam_pos.x) <= margin_x and absf(pos.y - cam_pos.y) <= margin_y:
				continue
			if pos.distance_squared_to(cam_pos) > range_sq:
				continue
		if not get_nearby_cars(pos, 50.0).is_empty():
			continue
		candidates.append(n_name)

	if candidates.is_empty():
		return

	var chosen: String = candidates[randi() % candidates.size()]
	var spawn_pos: Vector2 = (npc_nodes[chosen] as Dictionary)["pos"] as Vector2
	var npc: PedestrianNPC = PEDESTRIAN_SCENE.instantiate() as PedestrianNPC
	npc.setup(spawn_pos, chosen, self)
	npc.hit_taxi.connect(func(t: Taxi) -> void: taxi_hit_pedestrian.emit(t))
	city_map.get_entities_root().add_child(npc)
	active_npcs.append(npc)


func despawn_npc(npc: PedestrianNPC) -> void:
	active_npcs.erase(npc)
	if is_instance_valid(npc):
		npc.queue_free()


func get_npc_node(node_name: String) -> Dictionary:
	return npc_nodes.get(node_name, {}) as Dictionary


func get_node_pos(node_name: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if npc_nodes.has(node_name):
		return (npc_nodes[node_name] as Dictionary)["pos"] as Vector2
	if city_map != null and city_map.landmark_nodes.has(node_name):
		return city_map.landmark_nodes[node_name] as Vector2
	return fallback


func find_nearest_walkable_node(pos: Vector2, max_dist: float = 350.0) -> String:
	var best_name: String = ""
	var best_dist_sq: float = max_dist * max_dist
	for name_var in npc_nodes.keys():
		var n_name: String = str(name_var)
		var data: Dictionary = npc_nodes[n_name] as Dictionary
		if (data["next"] as Array).is_empty():
			continue
		var n_pos: Vector2 = data["pos"] as Vector2
		var d_sq: float = pos.distance_squared_to(n_pos)
		if d_sq < best_dist_sq and not city_map.line_intersects_building(pos, n_pos):
			best_dist_sq = d_sq
			best_name = n_name
	return best_name


func get_nearby_cars(pos: Vector2, radius: float = 70.0) -> Array[CarBase]:
	var out: Array[CarBase] = []
	var rad_sq: float = radius * radius
	if traffic_system != null:
		for car in traffic_system.active_cars:
			if is_instance_valid(car) and car.global_position.distance_squared_to(pos) <= rad_sq:
				out.append(car)
	if taxi_ref != null and is_instance_valid(taxi_ref):
		if taxi_ref.global_position.distance_squared_to(pos) <= rad_sq:
			out.append(taxi_ref)
	return out
