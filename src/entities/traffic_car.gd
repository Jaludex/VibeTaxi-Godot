class_name TrafficCar
extends CarBase

## Autonomous traffic vehicle following Tiled traffic-nodes with sensor-based yielding.

enum State { DRIVE, IDLE, CRASHED }

var current_state: State = State.DRIVE
var traffic_system: TrafficSystem = null
var target_position: Vector2 = Vector2.ZERO
var next_node_name: String = ""

@onready var _front_sensor: Area2D = $FrontSensor


func _ready() -> void:
	can_reverse = false
	super._ready()


func setup_traffic(def_key: String, pos: Vector2, p_target: Vector2, p_next_node: String, p_system: TrafficSystem) -> void:
	apply_vehicle_def(def_key, GameConstants.TRAFFIC_SPEED_SCALE)
	_finish_traffic_setup(pos, p_target, p_next_node, p_system)


func setup_traffic_def(def_res: VehicleDef, pos: Vector2, p_target: Vector2, p_next_node: String, p_system: TrafficSystem) -> void:
	apply_vehicle_resource(def_res, GameConstants.TRAFFIC_SPEED_SCALE)
	_finish_traffic_setup(pos, p_target, p_next_node, p_system)


func _finish_traffic_setup(pos: Vector2, p_target: Vector2, p_next_node: String, p_system: TrafficSystem) -> void:
	traffic_system = p_system
	global_position = pos
	target_position = p_target
	next_node_name = p_next_node
	set_heading((p_target - pos).angle())
	speed = max_speed * 0.5
	current_state = State.DRIVE
	if traffic_system != null and traffic_system.city_map != null:
		attach_silhouette(traffic_system.city_map)


func _physics_process(delta: float) -> void:
	decay_push(delta)
	match current_state:
		State.DRIVE:
			var should_brake: bool = _check_obstacles_ahead()
			step_driving(delta, target_position, true, should_brake)
			perform_move_and_detect()
			_advance_waypoint_if_reached()
		State.IDLE:
			speed = move_toward(speed, 0.0, friction * delta)
			velocity = Vector2(cos(heading_angle), sin(heading_angle)) * speed
			perform_move_and_detect()
		State.CRASHED:
			speed = move_toward(speed, 0.0, friction * 1.5 * delta)
			velocity = Vector2(cos(heading_angle), sin(heading_angle)) * speed
			perform_move_and_detect()
	update_silhouette()


func _check_obstacles_ahead() -> bool:
	if _front_sensor == null:
		return false

	for body in _front_sensor.get_overlapping_bodies():
		if body == self:
			continue
		if body is CarBase:
			var other: CarBase = body as CarBase
			var to_other: Vector2 = other.global_position - global_position
			if to_other.length_squared() >= 6400.0:
				continue
			var angle_diff: float = absf(wrapf(to_other.angle() - heading_angle, -PI, PI))
			if angle_diff < PI * 0.25:
				var other_diff: float = absf(wrapf((-to_other).angle() - other.heading_angle, -PI, PI))
				if other_diff < PI * 0.25:
					if get_instance_id() < other.get_instance_id():
						return true
				else:
					return true

	var forward_dir: Vector2 = Vector2(cos(heading_angle), sin(heading_angle))
	var right_dir: Vector2 = Vector2(-forward_dir.y, forward_dir.x)
	for area in _front_sensor.get_overlapping_areas():
		if area is PedestrianNPC:
			var npc: PedestrianNPC = area as PedestrianNPC
			if npc.current_state == PedestrianNPC.State.DEAD:
				continue
			var rel: Vector2 = npc.global_position - global_position
			var forward_dist: float = rel.dot(forward_dir)
			var lateral_dist: float = absf(rel.dot(right_dir))
			if forward_dist > -5.0 and forward_dist < 60.0 and lateral_dist < 22.0:
				return true

	return false


func _advance_waypoint_if_reached() -> void:
	if global_position.distance_squared_to(target_position) >= 900.0:
		return
	if traffic_system == null:
		queue_free()
		return

	if next_node_name.is_empty():
		var fallback_node: String = traffic_system.find_continuation_node(global_position, heading_angle)
		if not fallback_node.is_empty():
			var fb_pos: Variant = traffic_system.get_node_position(fallback_node)
			if fb_pos != null:
				target_position = fb_pos as Vector2
				next_node_name = traffic_system.get_node_next(fallback_node)
				return
		# Never vanish on-screen: park cleanly until camera moves away
		if traffic_system.is_offscreen(global_position):
			traffic_system.despawn_car(self)
		else:
			current_state = State.IDLE
		return

	var next_pos: Variant = traffic_system.get_node_position(next_node_name)
	if next_pos == null:
		next_node_name = ""
		return

	target_position = next_pos as Vector2
	next_node_name = traffic_system.get_node_next(next_node_name)


func _on_new_collision(collider: Object, normal: Vector2) -> void:
	super._on_new_collision(collider, normal)
	if collider is PropEntity:
		penalize_speed(0.5)
		(collider as PropEntity).on_hit_by_vehicle(self, -normal)
	elif collider is CarBase:
		var other: CarBase = collider as CarBase
		on_vehicle_collision(other)
		penalize_speed(0.6)
		other.penalize_speed(0.85)
	elif collider is StaticBody2D:
		if absf(speed) > GameConstants.WALL_CRASH_MIN_SPEED and traffic_system != null and traffic_system.city_map != null:
			traffic_system.city_map.spawn_sparks(global_position)


func on_vehicle_collision(other: CarBase) -> void:
	if is_crashed:
		return
	var rel_speed: float = (velocity - other.velocity).length()
	if (
		rel_speed >= GameConstants.TRAFFIC_CRASH_REL_SPEED
		or absf(speed) >= GameConstants.TRAFFIC_CRASH_REL_SPEED
		or absf(other.speed) >= GameConstants.TRAFFIC_CRASH_REL_SPEED
	):
		is_crashed = true
		current_state = State.CRASHED
		crashed.emit()
