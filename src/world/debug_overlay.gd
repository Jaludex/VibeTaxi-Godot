class_name DebugOverlay
extends Node2D

## Renders physics collision boxes, node graphs, and gamepad deadzone when physics_debug is enabled.

const DEBUG_FONT: Font = preload("res://assets/fonts/medium.ttf")

var city_map: CityMap = null
var _enabled: bool = false


func _ready() -> void:
	ConfigManager.config_changed.connect(_on_config_changed)
	_enabled = bool(ConfigManager.get_value("physics_debug", false))
	visible = _enabled


func _on_config_changed(key: String, val: Variant) -> void:
	if key == "physics_debug":
		_enabled = bool(val)
		visible = _enabled
		queue_redraw()


func _process(_delta: float) -> void:
	if _enabled:
		queue_redraw()


func _draw() -> void:
	if not _enabled or city_map == null:
		return

	# Static wall colliders
	for rect in city_map.collision_rects:
		draw_rect(rect, Color(1.0, 0.0, 0.0, 0.16), true)
		draw_rect(rect, Color(1.0, 0.4, 0.4, 0.85), false, 1.0)

	# Landmark nodes + labels
	for node_name_var in city_map.landmark_nodes.keys():
		var pos: Vector2 = city_map.landmark_nodes[node_name_var] as Vector2
		draw_rect(Rect2(pos - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), Color(0.0, 0.47, 1.0, 0.85), false, 1.0)
		draw_string(DEBUG_FONT, pos + Vector2(-24.0, -10.0), str(node_name_var), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	# Live entity hitboxes
	for ent in city_map.get_entities_root().get_children():
		if not is_instance_valid(ent) or not (ent is Node2D):
			continue
		var n2d: Node2D = ent as Node2D
		if ent is CarBase:
			var car: CarBase = ent as CarBase
			var cs: CollisionShape2D = car.collision_shape
			if cs != null and cs.shape is RectangleShape2D:
				var sz: Vector2 = (cs.shape as RectangleShape2D).size
				draw_set_transform(car.global_position, car.rotation, Vector2.ONE)
				draw_rect(Rect2(-sz * 0.5, sz), Color(1.0, 0.0, 0.0, 0.9), false, 1.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_circle(car.global_position, 2.0, Color.GREEN)
			if ent is Taxi and GameFlow.last_input_device == "gamepad":
				var dz: float = float(ConfigManager.get_value("gamepad_deadzone", 0.25))
				draw_arc(car.global_position, dz * GameConstants.MOUSE_MAX_SPEED_RADIUS, 0.0, TAU, 32, Color(1.0, 0.4, 0.4, 0.9), 1.0)
		elif ent is Area2D:
			draw_rect(Rect2(n2d.global_position - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), Color(1.0, 0.6, 0.0, 0.85), false, 1.0)
