class_name SkidMarks
extends Node2D

## Fixed-capacity ring buffer drawing fading tire skid marks in a single _draw pass.

const MAX_MARKS: int = 256
const LIFETIME: float = 2.5
const MARK_SIZE: Vector2 = Vector2(3.0, 3.0)
const HALF_SIZE: Vector2 = Vector2(1.5, 1.5)
const BASE_COLOR: Color = Color(0.14, 0.14, 0.14, 0.55)

var _positions: PackedVector2Array = PackedVector2Array()
var _expires: PackedFloat32Array = PackedFloat32Array()
var _head: int = 0
var _tail: int = 0
var _count: int = 0
var _now: float = 0.0


func _ready() -> void:
	_positions.resize(MAX_MARKS)
	_expires.resize(MAX_MARKS)
	set_process(false)


func add_mark(world_pos: Vector2) -> void:
	if _positions.is_empty():
		_positions.resize(MAX_MARKS)
		_expires.resize(MAX_MARKS)
	_positions[_head] = world_pos - HALF_SIZE
	_expires[_head] = _now + LIFETIME
	_head = (_head + 1) % MAX_MARKS
	if _count < MAX_MARKS:
		_count += 1
	else:
		_tail = (_tail + 1) % MAX_MARKS
	set_process(true)
	queue_redraw()


func clear_marks() -> void:
	_head = 0
	_tail = 0
	_count = 0
	_now = 0.0
	set_process(false)
	queue_redraw()


func get_active_count() -> int:
	return _count


func _process(delta: float) -> void:
	_now += delta
	while _count > 0 and _expires[_tail] <= _now:
		_tail = (_tail + 1) % MAX_MARKS
		_count -= 1
	if _count == 0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for i in _count:
		var idx: int = (_tail + i) % MAX_MARKS
		var alpha_frac: float = clampf((_expires[idx] - _now) / LIFETIME, 0.0, 1.0)
		if alpha_frac <= 0.0:
			continue
		var col: Color = BASE_COLOR
		col.a *= alpha_frac
		draw_rect(Rect2(_positions[idx], MARK_SIZE), col)
