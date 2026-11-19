class_name PassengerHUD
extends Control

## Right-side passenger HUD: VIBE comfort bar, animated rear-view window, and typewriter dialogue.

const NOTES_TEXTURE: Texture2D = preload("res://assets/graphics/music_notes.png")
const PEDS_TEXTURE: Texture2D = preload("res://assets/graphics/peds.png")

const BAR_ON_OFFSET: float = -150.0
const PORTRAIT_ON_OFFSET: float = -110.0
const DIALOGUE_ON_OFFSET: float = -220.0
const PANEL_OFF_OFFSET: float = 20.0

var passenger: Passenger = null
var taxi_ref: Taxi = null

var _p_state: String = "idle"
var _p_timer: float = 0.0
var _crash_start_time: float = 0.0
var _note_timer: float = 0.0
var _page_wait_timer: float = 0.0

var _bar_fill_style: StyleBoxFlat

@onready var _hide_dialogue_timer: Timer = $HideDialogueTimer
@onready var _clear_passenger_timer: Timer = $ClearPassengerTimer
@onready var _bar_panel: Panel = $BarPanel
@onready var _progress_bar: ProgressBar = $BarPanel/ProgressBar
@onready var _portrait_panel: Panel = $PortraitPanel
@onready var _portrait_sprite: Sprite2D = $PortraitPanel/PassengerSprite
@onready var _notes_root: Control = $PortraitPanel/NotesRoot
@onready var _dialogue_panel: Panel = $DialoguePanel
@onready var _typewriter: TypewriterBox = $DialoguePanel/TypewriterBox


func _edge_x(right_offset: float) -> float:
	var vp_w: float = get_viewport_rect().size.x
	if vp_w <= 0.0:
		vp_w = float(GameConstants.VIRTUAL_WIDTH)
	return vp_w + right_offset


func _sync_positions_immediate() -> void:
	var has_p: bool = passenger != null
	_bar_panel.position.x = _edge_x(BAR_ON_OFFSET if has_p else PANEL_OFF_OFFSET)
	_portrait_panel.position.x = _edge_x(PORTRAIT_ON_OFFSET if has_p else PANEL_OFF_OFFSET)
	_dialogue_panel.position.x = _edge_x(DIALOGUE_ON_OFFSET if not _hide_dialogue_timer.is_stopped() else PANEL_OFF_OFFSET)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_sync_positions_immediate()


func _ready() -> void:
	_bar_panel.position.x = _edge_x(PANEL_OFF_OFFSET)
	_portrait_panel.position.x = _edge_x(PANEL_OFF_OFFSET)
	_dialogue_panel.position.x = _edge_x(PANEL_OFF_OFFSET)

	_bar_fill_style = StyleBoxFlat.new()
	_bar_fill_style.bg_color = Color(0.2, 0.82, 0.35)
	_progress_bar.add_theme_stylebox_override("fill", _bar_fill_style)

	_hide_dialogue_timer.timeout.connect(hide_dialogue)
	_clear_passenger_timer.timeout.connect(_clear_passenger)


func bind_passenger(p: Passenger, show_dialogue_now: bool = true) -> void:
	_clear_passenger_timer.stop()
	passenger = p
	if not passenger.comfort_changed.is_connected(_on_comfort_changed):
		passenger.comfort_changed.connect(_on_comfort_changed)
	if not passenger.dialogue_requested.is_connected(show_text):
		passenger.dialogue_requested.connect(show_text)
	if not passenger.crash_reacted.is_connected(trigger_crash):
		passenger.crash_reacted.connect(trigger_crash)

	_progress_bar.value = passenger.comfort
	_update_bar_color(passenger.comfort)

	_p_state = "boarding"
	_p_timer = 0.0
	_portrait_sprite.visible = true
	_portrait_sprite.flip_h = false
	_portrait_sprite.position = Vector2(-40.0, 58.0)

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_bar_panel, "position:x", _edge_x(BAR_ON_OFFSET), 0.35)
	tween.tween_property(_portrait_panel, "position:x", _edge_x(PORTRAIT_ON_OFFSET), 0.35)

	if show_dialogue_now:
		show_greeting()


func show_greeting() -> void:
	if passenger != null:
		show_text(str(passenger.dialogues.get("enter", "Hello!")))


func trigger_crash() -> void:
	if passenger != null:
		_p_state = "crashed"
		_crash_start_time = _p_timer


func unbind_passenger() -> void:
	if passenger == null:
		return
	var farewell: String = str(
		passenger.dialogues.get("exit_good", "Excellent!")
		if passenger.comfort >= float(GameConstants.COMFORT_RULES["exit_good_threshold"])
		else passenger.dialogues.get("exit_bad", "Terrible ride...")
	)
	var total_time: float = show_text(farewell)
	_p_state = "exiting"
	_p_timer = 0.0
	_clear_passenger_timer.start(total_time + 0.35)


func _clear_passenger() -> void:
	passenger = null
	_p_state = "idle"
	_portrait_sprite.visible = false
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_bar_panel, "position:x", _edge_x(PANEL_OFF_OFFSET), 0.35)
	tween.tween_property(_portrait_panel, "position:x", _edge_x(PANEL_OFF_OFFSET), 0.35)


func show_text(text: String, display_duration: float = GameConstants.DIALOGUE_DISPLAY_TIME) -> float:
	var type_time: float = _typewriter.set_box_text(text)
	var total_time: float = type_time + display_duration
	_page_wait_timer = 0.0

	var tween: Tween = create_tween()
	tween.tween_property(_dialogue_panel, "position:x", _edge_x(DIALOGUE_ON_OFFSET), 0.3)

	_hide_dialogue_timer.start(total_time)
	return total_time


func hide_dialogue() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_dialogue_panel, "position:x", _edge_x(PANEL_OFF_OFFSET), 0.3)


func _on_comfort_changed(new_comfort: float) -> void:
	_progress_bar.value = new_comfort
	_update_bar_color(new_comfort)


func _update_bar_color(val: float) -> void:
	if val >= 60.0:
		_bar_fill_style.bg_color = Color(0.2, 0.82, 0.35)
	elif val >= 30.0:
		_bar_fill_style.bg_color = Color(0.9, 0.71, 0.16)
	else:
		_bar_fill_style.bg_color = Color(0.86, 0.24, 0.24)


func _process(delta: float) -> void:
	if is_instance_valid(passenger):
		_p_timer += delta
		_portrait_sprite.frame = passenger.get_current_frame_index()
		_update_portrait_motion()

		if taxi_ref != null and taxi_ref.is_vibe_mode() and passenger.is_riding():
			_note_timer += delta
			if _note_timer >= 0.25:
				_note_timer = 0.0
				_spawn_music_note()
	elif passenger != null:
		passenger = null

	if not _typewriter.is_typing and _typewriter.has_next_page():
		_page_wait_timer += delta
		if _page_wait_timer >= GameConstants.PASSENGER_NEXT_PAGE_TIME:
			_page_wait_timer = 0.0
			_typewriter.next_page()
	else:
		_page_wait_timer = 0.0


func _update_portrait_motion() -> void:
	var target_x: float = 44.0
	var base_y: float = 60.0
	match _p_state:
		"boarding":
			var prog: float = minf(1.0, _p_timer / 1.0)
			_portrait_sprite.position.x = lerpf(-40.0, target_x, prog)
			_portrait_sprite.position.y = base_y - absf(sin(_p_timer * 15.0)) * 10.0
			if prog >= 1.0:
				_p_state = "riding"
		"riding":
			_portrait_sprite.position.x = target_x
			_portrait_sprite.position.y = base_y + sin(_p_timer * 3.0) * 2.0
		"crashed":
			var elapsed: float = _p_timer - _crash_start_time
			var prog: float = elapsed / 1.2
			if prog >= 1.0:
				_p_state = "riding"
			else:
				var decay: float = maxf(0.0, 1.0 - prog)
				_portrait_sprite.position.x = target_x + sin(elapsed * 25.0) * 26.0 * decay
				_portrait_sprite.position.y = base_y + (sin(elapsed * 32.0) * 18.0 - absf(cos(elapsed * 16.0)) * 12.0) * decay
		"exiting":
			var prog: float = minf(1.0, _p_timer / 1.0)
			_portrait_sprite.flip_h = true
			_portrait_sprite.position.x = lerpf(target_x, 130.0, prog)
			_portrait_sprite.position.y = base_y - absf(sin(_p_timer * 15.0)) * 10.0


func _spawn_music_note() -> void:
	var note: Sprite2D = Sprite2D.new()
	note.texture = NOTES_TEXTURE
	note.region_enabled = true
	var idx: int = randi() % 20
	@warning_ignore("integer_division")
	var col: int = idx % 8
	@warning_ignore("integer_division")
	var row: int = idx / 8
	note.region_rect = Rect2(col * 12, row * 15, 12, 15)
	note.scale = Vector2(1.5, 1.5)
	note.position = _portrait_sprite.position + Vector2(0.0, -10.0)
	_notes_root.add_child(note)

	var drift: Vector2 = Vector2(randf_range(20.0, 60.0), randf_range(-60.0, -20.0)) * 1.5
	var tween: Tween = note.create_tween().set_parallel(true)
	tween.tween_property(note, "position", note.position + drift, 1.5)
	tween.tween_property(note, "modulate:a", 0.0, 1.5)
	tween.chain().tween_callback(note.queue_free)
