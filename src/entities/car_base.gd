class_name CarBase
extends CharacterBody2D

## Base vehicle controller with arcade steering, collision cooldowns, car pushing, and overhead silhouette.

signal crashed
signal collided_with(collider: Object, normal: Vector2)

const CARS_TEXTURE: Texture2D = preload("res://assets/graphics/cars.png")
const COLLISION_COOLDOWN_MS: int = 450

@export var vehicle_def: VehicleDef = null
@export var max_speed: float = 125.0
@export var acceleration: float = 90.0
@export var friction: float = 300.0
@export var turn_speed: float = 4.0
@export var reverse_speed_ratio: float = 0.2
@export var max_health: float = 100.0
@export var can_reverse: bool = true

var health: float = 100.0
var speed: float = 0.0
var heading_angle: float = 0.0
var is_crashed: bool = false
var prevent_movement: bool = false
var invincible: bool = false
var frame_index: int = 0
var push_velocity: Vector2 = Vector2.ZERO
var city_map: CityMap = null

var _prev_colliders: Dictionary = {}
var _collision_cooldowns: Dictionary = {}
var _silhouette_sprite: Sprite2D = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func apply_vehicle_resource(def_res: VehicleDef, speed_scale: float = 1.0) -> void:
	if def_res == null:
		return
	vehicle_def = def_res
	frame_index = def_res.frame_index
	max_speed = def_res.max_speed * speed_scale
	acceleration = def_res.acceleration
	friction = def_res.friction
	turn_speed = def_res.turn_speed
	reverse_speed_ratio = def_res.reverse_speed_ratio
	max_health = def_res.base_health
	health = max_health
	_sync_visual_and_hitbox()


func apply_vehicle_def(def_key: String, speed_scale: float = 1.0) -> void:
	var res_path: String = "res://resources/vehicles/%s.tres" % def_key
	var loaded: VehicleDef = load(res_path) as VehicleDef if ResourceLoader.exists(res_path) else null
	if loaded != null:
		apply_vehicle_resource(loaded, speed_scale)
	else:
		push_warning("CarBase: missing VehicleDef resource %s" % res_path)
		_sync_visual_and_hitbox()


func _ready() -> void:
	if vehicle_def != null:
		apply_vehicle_resource(vehicle_def)
	set_heading(heading_angle)
	_sync_visual_and_hitbox()


func _exit_tree() -> void:
	if is_instance_valid(_silhouette_sprite):
		_silhouette_sprite.queue_free()
	_silhouette_sprite = null


func attach_silhouette(map: CityMap) -> void:
	city_map = map
	if city_map == null or sprite == null:
		return
	if _silhouette_sprite == null:
		_silhouette_sprite = Sprite2D.new()
		_silhouette_sprite.texture = sprite.texture
		_silhouette_sprite.region_enabled = true
		_silhouette_sprite.region_rect = sprite.region_rect
		_silhouette_sprite.modulate = Color(0.0, 0.0, 0.0, 0.63)
		_silhouette_sprite.visible = false
		city_map.get_silhouettes_root().add_child(_silhouette_sprite)


func update_silhouette() -> void:
	if _silhouette_sprite == null or city_map == null:
		return
	_silhouette_sprite.global_position = global_position
	_silhouette_sprite.rotation = rotation
	_silhouette_sprite.visible = city_map.is_point_under_overhead(global_position)


func _sync_visual_and_hitbox() -> void:
	var rect: Rect2 = GameConstants.CAR_FRAME_RECTS[clampi(frame_index, 0, GameConstants.CAR_FRAME_RECTS.size() - 1)]
	if sprite != null:
		sprite.texture = CARS_TEXTURE
		sprite.region_enabled = true
		sprite.region_rect = rect
	if _silhouette_sprite != null:
		_silhouette_sprite.region_rect = rect
	if collision_shape != null and collision_shape.shape is RectangleShape2D:
		(collision_shape.shape as RectangleShape2D).size = rect.size


func set_heading(angle_rad: float) -> void:
	heading_angle = wrapf(angle_rad, -PI, PI)
	rotation = heading_angle + PI * 0.5


func apply_push(impulse: Vector2) -> void:
	push_velocity = (push_velocity + impulse).limit_length(100.0)


func decay_push(delta: float) -> void:
	push_velocity = push_velocity.move_toward(Vector2.ZERO, 550.0 * delta)


func step_driving(
	delta: float,
	target_pos: Vector2,
	is_accelerating: bool,
	is_braking_input: bool,
	eff_max_speed: float = -1.0,
	eff_accel: float = -1.0,
	eff_turn_speed: float = -1.0
) -> bool:
	var use_max_spd: float = eff_max_speed if eff_max_speed > 0.0 else max_speed
	var use_accel: float = eff_accel if eff_accel > 0.0 else acceleration
	var use_turn: float = eff_turn_speed if eff_turn_speed > 0.0 else turn_speed

	var accel: bool = is_accelerating
	var braking: bool = is_braking_input
	var reversing: bool = false

	if prevent_movement:
		accel = false
		braking = true
	elif is_braking_input and speed <= 0.5 and can_reverse:
		reversing = true
		braking = false

	var delta_vec: Vector2 = target_pos - global_position
	var dist: float = delta_vec.length()
	var target_angle: float = heading_angle
	if dist > 5.0:
		target_angle = delta_vec.angle() + (PI if reversing else 0.0)

	var angle_diff: float = wrapf(target_angle - heading_angle, -PI, PI)
	var dir_sign: float = -1.0 if reversing else 1.0
	var max_spd: float = use_max_spd * (reverse_speed_ratio if reversing else 1.0)
	var spd_abs: float = absf(speed)
	var spd_ratio: float = spd_abs / max_spd if max_spd > 0.0 else 0.0
	var turn_mult: float = (spd_abs / 30.0) if spd_abs < 30.0 else (1.5 - 0.9 * spd_ratio)
	var turn_amount: float = use_turn * turn_mult * delta * GameConstants.TURN_REDUCTION

	if absf(angle_diff) < turn_amount:
		set_heading(target_angle)
	else:
		set_heading(heading_angle + turn_amount * signf(angle_diff))

	var target_speed: float = 0.0
	var max_dist: float = GameConstants.MOUSE_MAX_SPEED_RADIUS
	if not reversing and dist < 15.0:
		target_speed = 0.0
	elif (accel or reversing) and not braking:
		var limit: float = max_spd if (reversing or dist >= max_dist) else max_spd * (dist / max_dist)
		target_speed = limit * dir_sign

	var rate: float = (
		use_accel * delta if absf(target_speed) > absf(speed)
		else friction * (3.0 if braking else 1.0) * delta
	)
	speed = move_toward(speed, target_speed, rate)

	velocity = Vector2(cos(heading_angle), sin(heading_angle)) * speed
	return speed != 0.0 or accel or reversing


func perform_move_and_detect() -> void:
	var drive_vel: Vector2 = velocity
	move_and_slide()

	var now_ms: int = Time.get_ticks_msec()
	var current_colliders: Dictionary = {}
	for i in get_slide_collision_count():
		var col: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = col.get_collider()
		if collider == null:
			continue
		var cid: int = collider.get_instance_id()
		current_colliders[cid] = true

		# Push only when actively driving into the other car (never while stopped in contact)
		if collider is CarBase:
			var other_car: CarBase = collider as CarBase
			var into_contact: float = drive_vel.dot(-col.get_normal())
			if into_contact > 12.0:
				other_car.apply_push(-col.get_normal() * minf(90.0, into_contact * 0.45))

		if not _prev_colliders.has(cid) and now_ms >= int(_collision_cooldowns.get(cid, 0)):
			_collision_cooldowns[cid] = now_ms + COLLISION_COOLDOWN_MS
			_on_new_collision(collider, col.get_normal())
	_prev_colliders = current_colliders

	if push_velocity.length_squared() > 0.25:
		var push_col: KinematicCollision2D = move_and_collide(push_velocity * get_physics_process_delta_time())
		if push_col != null:
			push_velocity = Vector2.ZERO


func _on_new_collision(collider: Object, normal: Vector2) -> void:
	collided_with.emit(collider, normal)


func penalize_speed(factor: float = 0.5) -> void:
	speed *= factor
	velocity *= factor


func take_damage(amount: float) -> void:
	if invincible or is_crashed or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		is_crashed = true
		crashed.emit()
