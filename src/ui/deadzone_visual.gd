class_name DeadzoneVisual
extends Control

## Live radial deadzone visualizer for gamepad left stick.

var deadzone: float = 0.25


func _init() -> void:
	custom_minimum_size = Vector2(44.0, 44.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var r_outer: float = maxf(8.0, minf(size.x, size.y) * 0.5 - 4.0)
	var r_dead: float = clampf(deadzone, 0.0, 1.0) * r_outer

	# Outer range + deadzone circle
	draw_circle(center, r_outer, Color(0.12, 0.08, 0.14))
	draw_circle(center, r_dead, Color(0.7, 0.2, 0.2, 0.35))
	draw_arc(center, r_outer, 0.0, TAU, 32, Color(0.7, 0.7, 0.78), 1.0)
	draw_arc(center, r_dead, 0.0, TAU, 28, Color(0.95, 0.35, 0.35), 1.0)

	# Crosshairs
	draw_line(center - Vector2(r_outer, 0.0), center + Vector2(r_outer, 0.0), Color(0.35, 0.35, 0.42), 1.0)
	draw_line(center - Vector2(0.0, r_outer), center + Vector2(0.0, r_outer), Color(0.35, 0.35, 0.42), 1.0)

	# Live stick position
	var raw: Vector2 = Vector2.ZERO
	if not Input.get_connected_joypads().is_empty():
		raw = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	var mag: float = raw.length()
	var clamped: Vector2 = raw.limit_length(1.0)
	var dot_pos: Vector2 = center + clamped * r_outer
	var dot_col: Color = Color(0.45, 0.45, 0.5)
	if mag >= deadzone:
		dot_col = Color(0.25, 0.9, 0.4)
	elif mag > 0.04:
		dot_col = Color(0.95, 0.75, 0.25)
	draw_circle(dot_pos, 3.0, dot_col)
