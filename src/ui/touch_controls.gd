class_name TouchControls
extends Control

## On-screen multi-touch overlay supporting virtual joystick and follow-finger driving modes.

signal pause_requested
signal radio_prev_requested
signal radio_next_requested

const JOY_RADIUS: float = 42.0
const JOY_KNOB_RADIUS: float = 17.0
const JOY_DEADZONE: float = 6.0
const MOUSE_TOUCH_ID: int = -99

var radio_ref: RadioTuner = null
var taxi_vibe_active: bool = false

var _joy_touch_id: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_current: Vector2 = Vector2.ZERO
var _joy_vector: Vector2 = Vector2.ZERO

var _drag_touch_id: int = -1
var _drag_screen_pos: Vector2 = Vector2.ZERO

var _brake_touches: Array[int] = []
var _drift_touches: Array[int] = []
var _mouse_pressed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_on_visibility_changed)
	ConfigManager.config_changed.connect(_on_config_changed)
	refresh_visibility()


func refresh_visibility() -> void:
	visible = ConfigManager.is_touch_controls_enabled()
	if not visible:
		reset_touches()
	queue_redraw()


func _on_visibility_changed() -> void:
	if not visible:
		reset_touches()


func _on_config_changed(key: String, _val: Variant) -> void:
	if key == "touch_controls" or key == "touch_mode":
		if key == "touch_mode":
			reset_touches()
		refresh_visibility()


func get_touch_mode() -> String:
	var mode: String = str(ConfigManager.get_value("touch_mode", "joystick"))
	return "drag" if mode == "drag" else "joystick"


func get_joystick_vector() -> Vector2:
	return _joy_vector if visible and get_touch_mode() == "joystick" else Vector2.ZERO


func is_drag_accelerating() -> bool:
	return visible and get_touch_mode() == "drag" and _drag_touch_id != -1


func get_drag_screen_pos() -> Vector2:
	return _drag_screen_pos


func is_brake_pressed() -> bool:
	return visible and not _brake_touches.is_empty()


func is_drift_pressed() -> bool:
	return visible and not _drift_touches.is_empty()


func reset_touches() -> void:
	_joy_touch_id = -1
	_joy_vector = Vector2.ZERO
	_drag_touch_id = -1
	_brake_touches.clear()
	_drift_touches.clear()
	_mouse_pressed = false
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED:
		if what != NOTIFICATION_RESIZED:
			reset_touches()
		else:
			queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused or GameFlow.has_modals():
		return

	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if simulate_touch(st.index, st.pressed, st.position):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if simulate_drag(sd.index, sd.position):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.device == -1 or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_mouse_pressed = mb.pressed
		if simulate_touch(MOUSE_TOUCH_ID, mb.pressed, mb.position):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if mm.device == -1 or not _mouse_pressed:
			return
		if simulate_drag(MOUSE_TOUCH_ID, mm.position):
			get_viewport().set_input_as_handled()


func simulate_touch(id: int, pressed: bool, pos: Vector2) -> bool:
	if not visible:
		return false
	var vp: Vector2 = _get_vp_size()

	if pressed:
		if _pause_rect().has_point(pos):
			AudioManager.play_sfx("press")
			reset_touches()
			pause_requested.emit()
			return true
		if _radio_prev_rect(vp).has_point(pos):
			radio_prev_requested.emit()
			queue_redraw()
			return true
		if _radio_next_rect(vp).has_point(pos):
			radio_next_requested.emit()
			queue_redraw()
			return true
		if _brake_rect(vp).has_point(pos):
			if not (id in _brake_touches):
				_brake_touches.append(id)
			queue_redraw()
			return true
		if _drift_rect(vp).has_point(pos):
			if not (id in _drift_touches):
				_drift_touches.append(id)
			queue_redraw()
			return true
		if radio_ref != null and radio_ref.handle_pointer_at(pos):
			queue_redraw()
			return true

		if get_touch_mode() == "drag":
			if _drag_touch_id == -1:
				_drag_touch_id = id
				_drag_screen_pos = pos
				queue_redraw()
				return true
		else:
			if pos.x <= vp.x * 0.6 and _joy_touch_id == -1:
				_joy_touch_id = id
				_joy_origin = Vector2(
					clampf(pos.x, JOY_RADIUS + 8.0, vp.x * 0.55 - JOY_RADIUS),
					clampf(pos.y, 48.0 + JOY_RADIUS, vp.y - JOY_RADIUS - 8.0)
				)
				_joy_current = pos
				_update_joy_vector()
				queue_redraw()
				return true
		return false

	var changed: bool = false
	if id in _brake_touches:
		_brake_touches.erase(id)
		changed = true
	if id in _drift_touches:
		_drift_touches.erase(id)
		changed = true
	if id == _joy_touch_id:
		_joy_touch_id = -1
		_joy_vector = Vector2.ZERO
		changed = true
	if id == _drag_touch_id:
		_drag_touch_id = -1
		changed = true
	if changed:
		queue_redraw()
	return changed


func simulate_drag(id: int, pos: Vector2) -> bool:
	if not visible:
		return false
	if id == _joy_touch_id:
		_joy_current = pos
		_update_joy_vector()
		queue_redraw()
		return true
	if id == _drag_touch_id:
		_drag_screen_pos = pos
		queue_redraw()
		return true
	return false


func _update_joy_vector() -> void:
	var delta_v: Vector2 = _joy_current - _joy_origin
	var dist: float = delta_v.length()
	if dist < JOY_DEADZONE:
		_joy_vector = Vector2.ZERO
		return
	var mag: float = clampf((dist - JOY_DEADZONE) / (JOY_RADIUS - JOY_DEADZONE), 0.0, 1.0)
	_joy_vector = delta_v.normalized() * mag


func _get_vp_size() -> Vector2:
	var sz: Vector2 = get_viewport_rect().size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return Vector2(float(GameConstants.VIRTUAL_WIDTH), float(GameConstants.VIRTUAL_HEIGHT))
	return sz


func _pause_rect() -> Rect2:
	return Rect2(108.0, 18.0, 34.0, 26.0)


func _radio_prev_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x - 148.0, vp.y - 114.0, 62.0, 32.0)


func _radio_next_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x - 76.0, vp.y - 114.0, 62.0, 32.0)


func _drift_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x - 148.0, vp.y - 72.0, 62.0, 56.0)


func _brake_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x - 76.0, vp.y - 72.0, 62.0, 56.0)


func _draw() -> void:
	if not visible:
		return
	var vp: Vector2 = _get_vp_size()
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 13

	# Steering visual
	if get_touch_mode() == "joystick":
		var origin: Vector2 = _joy_origin if _joy_touch_id != -1 else Vector2(62.0, vp.y - 62.0)
		var ring_alpha: float = 0.45 if _joy_touch_id != -1 else 0.24
		draw_circle(origin, JOY_RADIUS, Color(0.08, 0.1, 0.14, ring_alpha * 0.7))
		draw_arc(origin, JOY_RADIUS, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, ring_alpha), 1.5)
		var knob_offset: Vector2 = Vector2.ZERO
		if _joy_touch_id != -1:
			knob_offset = (_joy_current - _joy_origin).limit_length(JOY_RADIUS)
		draw_circle(origin + knob_offset, JOY_KNOB_RADIUS, Color(1.0, 0.86, 0.2, 0.8 if _joy_touch_id != -1 else 0.38))
	elif _drag_touch_id != -1:
		draw_arc(_drag_screen_pos, 18.0, 0.0, TAU, 24, Color(1.0, 0.86, 0.2, 0.75), 1.5)
		draw_circle(_drag_screen_pos, 4.0, Color(1.0, 0.86, 0.2, 0.85))

	# Action buttons (Drift left of Brake; Radio < > arrows above them)
	var brk_active: bool = not _brake_touches.is_empty()
	_draw_touch_btn(_brake_rect(vp), I18n.t("touch_brake"), Color(0.85, 0.24, 0.24, 0.72 if brk_active else 0.44), Color(1.0, 0.55, 0.55, 0.88), font, fsize)

	var drf_active: bool = not _drift_touches.is_empty()
	var drf_bg: Color = Color(0.15, 0.75, 0.9, 0.78 if drf_active else 0.5) if taxi_vibe_active else Color(0.2, 0.24, 0.3, 0.28)
	var drf_border: Color = Color(0.4, 1.0, 1.0, 0.92) if taxi_vibe_active else Color(0.6, 0.65, 0.7, 0.4)
	_draw_touch_btn(_drift_rect(vp), I18n.t("touch_drift"), drf_bg, drf_border, font, fsize)

	var radio_bg: Color = Color(0.12, 0.16, 0.24, 0.55)
	var radio_border: Color = Color(1.0, 0.86, 0.2, 0.82)
	var r_prev: Rect2 = _radio_prev_rect(vp)
	var r_next: Rect2 = _radio_next_rect(vp)
	_draw_touch_btn(r_prev, "", radio_bg, radio_border, font, fsize)
	_draw_touch_btn(r_next, "", radio_bg, radio_border, font, fsize)
	_draw_arrow(r_prev.get_center(), -1.0, radio_border)
	_draw_arrow(r_next.get_center(), 1.0, radio_border)

	_draw_touch_btn(_pause_rect(), "||", Color(0.1, 0.12, 0.18, 0.55), Color(0.9, 0.9, 0.95, 0.72), font, fsize)


func _draw_arrow(center: Vector2, dir: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(-4.0 * dir, -6.0),
		center + Vector2(5.0 * dir, 0.0),
		center + Vector2(-4.0 * dir, 6.0),
	])
	draw_polyline(pts, col, 2.2)


func _draw_touch_btn(rect: Rect2, label: String, bg: Color, border: Color, font: Font, fsize: int) -> void:
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 1.5)
	if not label.is_empty() and font != null:
		var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
		var pos: Vector2 = rect.position + Vector2((rect.size.x - text_size.x) * 0.5, (rect.size.y + text_size.y * 0.65) * 0.5)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1.0, 1.0, 1.0, clampf(border.a + 0.1, 0.45, 1.0)))
