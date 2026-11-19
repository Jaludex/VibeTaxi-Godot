class_name DestinationArrow
extends Sprite2D

## Points toward the active target (world pos), hovering above if on-screen or hugging the screen edge.

var target_world_pos: Vector2 = Vector2.ZERO
var active: bool = false
var _anim_time: float = 0.0
var _radius_progress: float = 1.0
var _tween: Tween = null


func _ready() -> void:
	texture = preload("res://assets/graphics/arrow.png")
	visible = false


func activate(world_pos: Vector2, animate_outward: bool = true) -> void:
	target_world_pos = world_pos
	active = true
	visible = true
	if animate_outward:
		_radius_progress = 0.0
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "_radius_progress", 1.0, 0.7)
	else:
		_radius_progress = 1.0


func deactivate() -> void:
	active = false
	visible = false


func update_arrow(delta: float, camera: Camera2D) -> void:
	if not active or camera == null:
		visible = false
		return
	visible = true
	_anim_time += delta

	var cam_center: Vector2 = camera.get_screen_center_position()
	var vp_size: Vector2 = get_viewport_rect().size
	var vw: float = vp_size.x
	var vh: float = vp_size.y
	var cam_top_left: Vector2 = cam_center - Vector2(vw * 0.5, vh * 0.5)
	var margin: float = 20.0

	if (
		target_world_pos.x >= cam_top_left.x + margin
		and target_world_pos.x <= cam_top_left.x + vw - margin
		and target_world_pos.y >= cam_top_left.y + margin
		and target_world_pos.y <= cam_top_left.y + vh - margin
	):
		rotation = PI * 0.5
		var bob: float = (sin(_anim_time * 6.0) + 1.0) * 5.0
		position = (target_world_pos - cam_top_left) + Vector2(0.0, -40.0 + bob)
	else:
		var delta_vec: Vector2 = target_world_pos - cam_center
		var angle: float = delta_vec.angle()
		rotation = angle
		var half_w: float = vw * 0.5 - 10.0
		var half_h: float = vh * 0.5 - 10.0
		var rx: float = INF if is_zero_approx(cos(angle)) else absf(half_w / cos(angle))
		var ry: float = INF if is_zero_approx(sin(angle)) else absf(half_h / sin(angle))
		var target_r: float = minf(rx, ry)
		var r: float = 40.0 + (target_r - 40.0) * _radius_progress
		position = Vector2(vw * 0.5, vh * 0.5) + Vector2(cos(angle), sin(angle)) * r
