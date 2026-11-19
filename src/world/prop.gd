@tool
class_name PropEntity
extends RigidBody2D

## Destructible roadside prop (cone, hydrant, mailbox, etc.) that spins and fades on impact.

const PROPS_COLUMNS: int = 18
const BURST_SCENE: PackedScene = preload("res://src/effects/burst_particles.tscn")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D

@export var tile_index: int = 6:
	set(v):
		tile_index = v
		_sync_sprite_region()
@export var damage_amount: float = 5.0
@export var particle_colors: Array[Color] = []
@export var particle_duration: float = 0.0
var _destroyed: bool = false


func setup(pos: Vector2, p_tile_index: int) -> void:
	position = pos
	tile_index = p_tile_index
	var def: Dictionary = GameConstants.PROP_DEFS.get(tile_index, {}) as Dictionary
	damage_amount = float(def.get("damage", 5.0))
	particle_colors.clear()
	for col in (def.get("particles", []) as Array):
		if col is Color:
			particle_colors.append(col as Color)
	particle_duration = float(def.get("duration", 0.0))


func _ready() -> void:
	_sync_sprite_region()
	if Engine.is_editor_hint():
		return
	gravity_scale = 0.0
	linear_damp = 3.0
	angular_damp = 1.5
	sleeping = true


func _sync_sprite_region() -> void:
	var spr: Sprite2D = _sprite if _sprite != null else get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		return
	@warning_ignore("integer_division")
	var atlas_pos: Vector2 = Vector2((tile_index % PROPS_COLUMNS) * 16, (tile_index / PROPS_COLUMNS) * 16)
	spr.region_enabled = true
	spr.region_rect = Rect2(atlas_pos, Vector2(16, 16))


func on_hit_by_vehicle(vehicle: Node, impact_dir: Vector2) -> void:
	if _destroyed:
		return
	_destroyed = true

	if vehicle != null and vehicle.has_method("take_damage"):
		vehicle.call("take_damage", damage_amount)

	# Disable further collisions immediately while visual tumble plays
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if _shape != null:
		_shape.set_deferred("disabled", true)

	sleeping = false
	apply_central_impulse(impact_dir.normalized() * 60.0)
	_spawn_particles()

	var rot_dir: float = -1.0 if randf() < 0.5 else 1.0
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "rotation", _sprite.rotation + rot_dir * (PI * 0.5), 0.2)
	tween.tween_property(_sprite, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)


func _spawn_particles() -> void:
	if particle_colors.is_empty():
		return
	var particles: CPUParticles2D = BURST_SCENE.instantiate() as CPUParticles2D
	particles.z_index = 6
	particles.lifetime = 0.4
	add_child(particles)
	particles.call(
		"trigger",
		particle_colors[0],
		16 if particle_duration > 0.0 else 12,
		particle_duration
	)
