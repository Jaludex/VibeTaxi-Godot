class_name PedestrianNPC
extends Area2D

## Autonomous sidewalk pedestrian with vehicle yielding, knockback physics, and recovery.

signal hit_taxi(taxi: Taxi)

enum State { WALKING, WAITING_CAR, HIT, DOWN, GETTING_UP, DESPAWNING, DEAD }

const DESPAWN_OFFSETS: Dictionary = {
	"up": Vector2(0.0, -1.0),
	"down": Vector2(0.0, 1.0),
	"left": Vector2(-1.0, 0.0),
	"right": Vector2(1.0, 0.0),
	"rigth": Vector2(1.0, 0.0),
}

var current_state: State = State.WALKING
var pedestrian_system: PedestrianSystem = null
var current_node: String = ""
var previous_node: String = ""
var target_node: String = ""
var target_pos: Vector2 = Vector2.ZERO

var blocked_node: String = ""
var blocked_timer: float = 0.0

var move_speed: float = 35.0
var _walk_timer: float = 0.0
var _wait_timer: float = 0.0
var _total_wait_time: float = 0.0
var _check_car_timer: float = 0.0

var _hit_timer: float = 0.0
var _hit_vel: Vector2 = Vector2.ZERO
var _down_timer: float = 0.0
var _down_duration: float = 1.4
var _getup_timer: float = 0.0
var _getup_start_angle: float = 0.0
var _despawn_timer: float = 0.0
var _despawn_dir: Vector2 = Vector2(0.0, -1.0)

var _idle_frames: Array = [0, 1]
var _walk_frames: Array = [2, 3, 4, 5]
var _active_frames: Array = []
var _anim_timer: float = 0.0
var _anim_interval: float = 0.15
var _anim_idx: int = 0

@onready var _sprite: Sprite2D = $Sprite2D


func setup(pos: Vector2, start_node: String, p_system: PedestrianSystem, def_key: String = "") -> void:
	global_position = pos
	current_node = start_node
	pedestrian_system = p_system

	var keys: Array = GameConstants.PASSENGER_DEFS.keys()
	var chosen: String = def_key if GameConstants.PASSENGER_DEFS.has(def_key) else str(keys[randi() % keys.size()])
	var def: Dictionary = GameConstants.PASSENGER_DEFS[chosen] as Dictionary
	_idle_frames = def["idle"] as Array
	_walk_frames = def["walk"] as Array

	move_speed = randf_range(28.0, 42.0)
	_walk_timer = randf()
	_check_car_timer = randf_range(0.0, 0.2)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_set_anim("walk")
	_select_next_node()


func _process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	if blocked_timer > 0.0:
		blocked_timer = maxf(0.0, blocked_timer - delta)

	var on_screen: bool = _is_near_camera()
	if on_screen and not _active_frames.is_empty():
		_anim_timer += delta
		if _anim_timer >= _anim_interval:
			_anim_timer = fmod(_anim_timer, _anim_interval)
			_anim_idx = (_anim_idx + 1) % _active_frames.size()
			_sprite.frame = int(_active_frames[_anim_idx])

	match current_state:
		State.WALKING:
			_process_walking(delta, on_screen)
		State.WAITING_CAR:
			_process_waiting(delta, on_screen)
		State.HIT:
			_process_hit(delta)
		State.DOWN:
			_process_down(delta)
		State.GETTING_UP:
			_process_getting_up(delta)
		State.DESPAWNING:
			_process_despawning(delta, on_screen)


func _is_near_camera() -> bool:
	if pedestrian_system == null or pedestrian_system.camera_ref == null:
		return true
	var cam_pos: Vector2 = pedestrian_system.camera_ref.get_screen_center_position()
	var vp_size: Vector2 = pedestrian_system.camera_ref.get_viewport_rect().size if pedestrian_system.camera_ref.is_inside_tree() else Vector2(GameConstants.VIRTUAL_WIDTH, GameConstants.VIRTUAL_HEIGHT)
	return (
		absf(global_position.x - cam_pos.x) <= vp_size.x * 0.5 + 80.0
		and absf(global_position.y - cam_pos.y) <= vp_size.y * 0.5 + 80.0
	)


func _set_anim(anim_name: String) -> void:
	var target_frames: Array = _walk_frames if anim_name == "walk" else _idle_frames
	var target_interval: float = 0.15 if anim_name == "walk" else 0.4
	if _active_frames == target_frames:
		return
	_active_frames = target_frames
	_anim_interval = target_interval
	_anim_timer = 0.0
	_anim_idx = 0
	if _sprite != null and not _active_frames.is_empty():
		_sprite.frame = int(_active_frames[0])


func _process_walking(delta: float, on_screen: bool) -> void:
	if on_screen:
		_walk_timer += delta
		_sprite.position.y = -absf(sin(_walk_timer * 12.0)) * 3.5
		_check_car_timer -= delta
		if _check_car_timer <= 0.0:
			_check_car_timer = 0.15
			if _check_car_hazard():
				current_state = State.WAITING_CAR
				_wait_timer = 0.3
				_set_anim("idle")
				return
	else:
		_sprite.position.y = 0.0

	var diff: Vector2 = target_pos - global_position
	if diff.x != 0.0:
		_sprite.flip_h = diff.x < 0.0

	var step: float = move_speed * delta
	var dist_sq: float = diff.length_squared()
	if dist_sq <= step * step or dist_sq < 16.0:
		global_position = target_pos
		previous_node = current_node
		current_node = target_node
		_select_next_node()
	else:
		global_position += diff.normalized() * step


func _process_waiting(delta: float, on_screen: bool) -> void:
	_wait_timer -= delta
	_total_wait_time += delta
	_sprite.position.y = 0.0

	if _total_wait_time >= 4.0:
		_total_wait_time = 0.0
		var blocked_dest: String = target_node
		blocked_node = blocked_dest
		blocked_timer = 8.0
		target_node = current_node
		previous_node = blocked_dest
		target_pos = pedestrian_system.get_node_pos(target_node, global_position)
		current_state = State.WALKING
		_set_anim("walk")
		return

	if _wait_timer <= 0.0:
		current_state = State.WALKING
		_set_anim("walk")
		if on_screen and _check_car_hazard():
			current_state = State.WAITING_CAR
			_wait_timer = 0.3
			_set_anim("idle")


func _process_hit(delta: float) -> void:
	_hit_timer += delta
	var duration: float = 0.7
	var progress: float = minf(1.0, _hit_timer / duration)
	var decay: float = maxf(0.0, 1.0 - progress)
	var step: Vector2 = _hit_vel * decay * delta

	if pedestrian_system != null and pedestrian_system.city_map != null:
		var map: CityMap = pedestrian_system.city_map
		var sweep: Rect2 = Rect2(global_position, Vector2.ZERO).expand(global_position + step).grow(12.0)
		var nearby_walls: Array[Rect2] = []
		for r in map.collision_rects:
			if r.intersects(sweep):
				nearby_walls.append(r)

		var next_x: float = global_position.x + step.x
		var box_x: Rect2 = Rect2(next_x - 7.0, global_position.y - 7.0, 14.0, 14.0)
		for r in nearby_walls:
			if r.intersects(box_x):
				_hit_vel.x = -_hit_vel.x * 0.3
				next_x = (r.position.x - 7.5) if step.x > 0.0 else (r.end.x + 7.5)
				break
		global_position.x = next_x

		var next_y: float = global_position.y + step.y
		var box_y: Rect2 = Rect2(global_position.x - 7.0, next_y - 7.0, 14.0, 14.0)
		for r in nearby_walls:
			if r.intersects(box_y):
				_hit_vel.y = -_hit_vel.y * 0.3
				next_y = (r.position.y - 7.5) if step.y > 0.0 else (r.end.y + 7.5)
				break
		global_position.y = next_y
		if not nearby_walls.is_empty():
			global_position = map.resolve_point_outside_buildings(global_position, 7.5)
	else:
		global_position += step

	_sprite.position.y = -sin(progress * PI) * 16.0
	_sprite.rotation = deg_to_rad(sin(progress * PI * 2.5) * 65.0)

	if _hit_timer >= duration:
		current_state = State.DOWN
		_down_timer = 0.0
		_down_duration = randf_range(1.2, 1.8)
		_sprite.position.y = 0.0
		_sprite.rotation = deg_to_rad(85.0 if _hit_vel.x >= 0.0 else -85.0)
		_set_anim("idle")


func _process_down(delta: float) -> void:
	_down_timer += delta
	var base_ang: float = deg_to_rad(85.0 if _hit_vel.x >= 0.0 else -85.0)
	_sprite.rotation = base_ang + sin(_down_timer * 10.0) * 0.06
	if _down_timer >= _down_duration:
		current_state = State.GETTING_UP
		_getup_timer = 0.0
		_getup_start_angle = _sprite.rotation


func _process_getting_up(delta: float) -> void:
	_getup_timer += delta
	var t: float = minf(1.0, _getup_timer / 0.5)
	var ease_t: float = 1.0 - pow(1.0 - t, 3.0)
	_sprite.rotation = _getup_start_angle * (1.0 - ease_t)
	_sprite.position.y = -sin(t * PI) * 4.0
	if t >= 1.0:
		_recover_from_hit()


func _process_despawning(delta: float, on_screen: bool) -> void:
	_despawn_timer += delta
	var progress: float = minf(1.0, _despawn_timer / 0.5)
	_sprite.modulate.a = 1.0 - progress
	global_position += _despawn_dir * 20.0 * delta
	if on_screen:
		_walk_timer += delta
		_sprite.position.y = -absf(sin(_walk_timer * 12.0)) * 3.5
	if progress >= 1.0:
		current_state = State.DEAD
		if pedestrian_system != null:
			pedestrian_system.despawn_npc(self)
		else:
			queue_free()


func _select_next_node() -> void:
	if pedestrian_system == null:
		current_state = State.DEAD
		return
	var node_info: Dictionary = pedestrian_system.get_npc_node(current_node)
	if node_info.is_empty():
		current_state = State.DEAD
		pedestrian_system.despawn_npc(self)
		return

	var raw_next: Array = node_info.get("next", []) as Array
	var next_nodes: Array[String] = []
	for n_var in raw_next:
		var n: String = str(n_var)
		if n != current_node and not next_nodes.has(n):
			next_nodes.append(n)

	var dir_name: String = str(node_info.get("dir_despawn", "up")).to_lower()
	if bool(node_info.get("despawn", false)) and (next_nodes.is_empty() or randf() < 0.45):
		_start_despawn(dir_name)
		return
	if next_nodes.is_empty():
		_start_despawn(dir_name)
		return

	if blocked_timer > 0.0 and next_nodes.has(blocked_node):
		var filtered: Array[String] = []
		for n in next_nodes:
			if n != blocked_node:
				filtered.append(n)
		if filtered.is_empty():
			_start_despawn(dir_name)
			return
		next_nodes = filtered

	var forward_nodes: Array[String] = []
	for n in next_nodes:
		if n != previous_node:
			forward_nodes.append(n)

	if not forward_nodes.is_empty():
		if next_nodes.has(previous_node) and randf() < 0.15:
			target_node = previous_node
		else:
			target_node = forward_nodes[randi() % forward_nodes.size()]
	elif next_nodes.has(previous_node):
		target_node = previous_node
	else:
		target_node = next_nodes[randi() % next_nodes.size()]

	target_pos = pedestrian_system.get_node_pos(target_node, global_position)
	_total_wait_time = 0.0


func _recover_from_hit() -> void:
	_sprite.rotation = 0.0
	_sprite.position.y = 0.0
	if pedestrian_system != null and pedestrian_system.city_map != null:
		global_position = pedestrian_system.city_map.resolve_point_outside_buildings(global_position, 7.5)
		var safe_node: String = pedestrian_system.find_nearest_walkable_node(global_position, 350.0)
		if not safe_node.is_empty():
			current_node = safe_node
			target_node = safe_node
			target_pos = pedestrian_system.get_node_pos(safe_node, global_position)
			previous_node = ""
			blocked_node = ""
			blocked_timer = 0.0
			current_state = State.WALKING
			_set_anim("walk")
			return
	_start_despawn("up")


func _start_despawn(dir_name: String) -> void:
	current_state = State.DESPAWNING
	_despawn_timer = 0.0
	_despawn_dir = DESPAWN_OFFSETS.get(dir_name, Vector2(0.0, -1.0)) as Vector2
	_set_anim("walk")


func _check_car_hazard() -> bool:
	if pedestrian_system == null:
		return false
	var cars: Array[CarBase] = pedestrian_system.get_nearby_cars(global_position, 70.0)
	if cars.is_empty():
		return false
	var to_target: Vector2 = target_pos - global_position
	var path_dist: float = to_target.length()
	if path_dist <= 0.01:
		return false
	var dir: Vector2 = to_target / path_dist
	var lookahead: float = minf(path_dist, 48.0)
	for car in cars:
		var rel: Vector2 = car.global_position - global_position
		var forward: float = rel.dot(dir)
		if forward > 0.0 and forward <= lookahead:
			var lateral: float = absf(rel.x * -dir.y + rel.y * dir.x)
			if lateral <= 18.0:
				return true
	return false


func _on_body_entered(body: Node) -> void:
	if current_state in [State.HIT, State.DOWN, State.GETTING_UP, State.DEAD]:
		return
	if body is CarBase:
		var car: CarBase = body as CarBase
		on_hit_by_car(car.global_position, car.speed)
		if pedestrian_system != null and pedestrian_system.city_map != null:
			pedestrian_system.city_map.spawn_sparks(global_position)
			if not pedestrian_system.city_map.muted:
				AudioManager.play_sfx("crash_car", 0.35 if car is Taxi else 0.25)
		if car is Taxi:
			car.penalize_speed(0.8)
			hit_taxi.emit(car as Taxi)
		elif car is TrafficCar:
			car.speed = 0.0


func on_hit_by_car(car_pos: Vector2, car_speed: float) -> void:
	if current_state in [State.HIT, State.DOWN, State.GETTING_UP, State.DEAD]:
		return
	current_state = State.HIT
	_hit_timer = 0.0
	_set_anim("idle")
	var away: Vector2 = global_position - car_pos
	if away.length_squared() < 0.01:
		away = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	var launch_spd: float = clampf(absf(car_speed) * 1.5, 90.0, 220.0)
	_hit_vel = away.normalized() * launch_spd
