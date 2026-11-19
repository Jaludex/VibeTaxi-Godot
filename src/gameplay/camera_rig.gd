class_name CameraRig
extends Camera2D

## Top-down 2D camera with exponential smoothing, map clamping, and decay shake.

var follow_target: Node2D = null
var follow_rate: float = GameConstants.CAMERA_FOLLOW_RATE
var _shake_magnitude: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0


func set_bounds(map_rect: Rect2) -> void:
	limit_left = int(map_rect.position.x)
	limit_top = int(map_rect.position.y)
	limit_right = int(map_rect.end.x)
	limit_bottom = int(map_rect.end.y)


func snap_to(pos: Vector2) -> void:
	global_position = pos
	reset_smoothing()


func shake(magnitude: float, duration: float) -> void:
	_shake_magnitude = magnitude
	_shake_duration = maxf(0.01, duration)
	_shake_timer = _shake_duration


func _process(delta: float) -> void:
	if follow_target != null and is_instance_valid(follow_target):
		var factor: float = 1.0 - exp(-follow_rate * delta)
		global_position = global_position.lerp(follow_target.global_position, factor)

	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		var decay: float = _shake_timer / _shake_duration
		var cur_mag: float = _shake_magnitude * decay
		offset = Vector2(randf_range(-cur_mag, cur_mag), randf_range(-cur_mag, cur_mag))
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
