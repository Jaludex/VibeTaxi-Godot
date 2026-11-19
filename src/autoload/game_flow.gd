extends Node

## Manages scene transitions, global fade overlay, modal stack, FPS counter, and focus pause.

signal input_device_changed(device: String)

var tutorial_enabled: bool = false
var last_input_device: String = "mouse"
var pending_play_params: Dictionary = {}

@onready var _overlay_layer: CanvasLayer = $OverlayLayer
@onready var _fade_rect: ColorRect = $OverlayLayer/FadeRect
@onready var _fps_label: Label = $OverlayLayer/FPSLabel
var _modal_stack: Array[Control] = []
var _modal_focus_stack: Array[Control] = []
var _is_transitioning: bool = false


func _ready() -> void:
	_ensure_ui_joypad_bindings()
	ConfigManager.config_changed.connect(_on_config_changed)
	get_tree().node_added.connect(_on_tree_node_added)
	_refresh_fps_visibility()


func _ensure_ui_joypad_bindings() -> void:
	_add_joy_button_if_missing(&"ui_accept", JOY_BUTTON_A)
	_add_joy_button_if_missing(&"ui_cancel", JOY_BUTTON_B)


func _add_joy_button_if_missing(action: StringName, btn_idx: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == btn_idx:
			return
	var joy_ev: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_ev.button_index = btn_idx
	InputMap.action_add_event(action, joy_ev)


func _on_tree_node_added(node: Node) -> void:
	if node is Control:
		var ctrl: Control = node as Control
		if ctrl is BaseButton or ctrl is Slider:
			ctrl.mouse_entered.connect(func() -> void:
				if not is_instance_valid(ctrl):
					return
				if ctrl.get_focus_mode_with_override() == Control.FOCUS_NONE:
					return
				if ctrl is BaseButton and (ctrl as BaseButton).disabled:
					return
				if last_input_device == "gamepad" and Input.get_last_mouse_velocity().length_squared() <= 1.0:
					return
				ctrl.grab_focus()
			)


func _exit_tree() -> void:
	TiledMapLoader.clear_cache()


func _process(_delta: float) -> void:
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		ConfigManager.toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_input_device("touch")
	elif event is InputEventMouseButton or (event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0):
		if event.device != -1:
			_set_input_device("mouse")
	elif event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and ke.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			_set_input_device("keyboard")
	elif event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event as InputEventJoypadMotion
		var dz: float = float(ConfigManager.get_value("gamepad_deadzone", 0.25))
		if absf(jm.axis_value) >= dz:
			_set_input_device("gamepad")
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_set_input_device("gamepad")

	if _is_ui_nav_event(event) and get_viewport().gui_get_focus_owner() == null:
		var in_menu: bool = not _modal_stack.is_empty() or not (get_tree().current_scene is PlayScene)
		if in_menu:
			var scope: Node = get_top_modal() if not _modal_stack.is_empty() else get_tree().current_scene
			var first_ctrl: Control = _find_first_focusable(scope)
			if first_ctrl != null:
				first_ctrl.grab_focus()
				get_viewport().set_input_as_handled()


func _is_ui_nav_event(event: InputEvent) -> bool:
	return (
		event.is_action_pressed(&"ui_up")
		or event.is_action_pressed(&"ui_down")
		or event.is_action_pressed(&"ui_left")
		or event.is_action_pressed(&"ui_right")
	)


func _find_first_focusable(root: Node) -> Control:
	if root == null:
		return null
	if root is Control:
		var ctrl: Control = root as Control
		if not ctrl.visible:
			return null
		if (ctrl is BaseButton or ctrl is Slider or ctrl is LineEdit) and ctrl.get_focus_mode_with_override() != Control.FOCUS_NONE:
			if not (ctrl is BaseButton and (ctrl as BaseButton).disabled):
				return ctrl
	for child in root.get_children():
		var found: Control = _find_first_focusable(child)
		if found != null:
			return found
	return null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if what == NOTIFICATION_APPLICATION_PAUSED or bool(ConfigManager.get_value("pause_on_focus_loss", true)):
			var current: Node = get_tree().current_scene
			if current != null and current.has_method("request_focus_pause"):
				current.call("request_focus_pause")
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back_request()


func handle_back_request() -> void:
	var press_ev: InputEventAction = InputEventAction.new()
	press_ev.action = &"ui_cancel"
	press_ev.pressed = true
	var top: Control = get_top_modal()
	if top != null:
		if top.has_method("_unhandled_input"):
			top.call("_unhandled_input", press_ev)
		return
	var current: Node = get_tree().current_scene
	if current is PlayScene:
		if current.has_method("request_focus_pause"):
			current.call("request_focus_pause")
	elif current != null and current.has_method("_unhandled_input"):
		current.call("_unhandled_input", press_ev)


func _set_input_device(device: String) -> void:
	if last_input_device != device:
		last_input_device = device
		input_device_changed.emit(device)


func _on_config_changed(key: String, _val: Variant) -> void:
	if key == "show_fps":
		_refresh_fps_visibility()


func _refresh_fps_visibility() -> void:
	if _fps_label != null:
		_fps_label.visible = bool(ConfigManager.get_value("show_fps", false))


func change_scene(scene_path: String, fade_out_sec: float = 0.5, fade_in_sec: float = 0.5) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	if fade_out_sec > 0.0:
		var tween_out: Tween = create_tween()
		tween_out.tween_property(_fade_rect, "color:a", 1.0, fade_out_sec)
		await tween_out.finished

	clear_modals()
	get_tree().paused = false
	var err: Error = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("GameFlow: failed to change scene to %s (err %d)" % [scene_path, err])

	await get_tree().process_frame
	if fade_in_sec > 0.0:
		var tween_in: Tween = create_tween()
		tween_in.tween_property(_fade_rect, "color:a", 0.0, fade_in_sec)
		await tween_in.finished
	else:
		_fade_rect.color.a = 0.0

	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false


func start_gameplay(mode: String, extra_params: Dictionary = {}) -> void:
	pending_play_params = extra_params.duplicate(true)
	pending_play_params["mode"] = mode
	pending_play_params["tutorial_mode"] = tutorial_enabled and (mode == "workday" or mode == "arcade")
	await change_scene("res://src/gameplay/play_scene.tscn", 0.6, 0.0)


func push_modal(modal: Control, pause_tree: bool = true) -> void:
	if modal == null:
		return
	var prev_focus: Control = get_viewport().gui_get_focus_owner()
	_modal_focus_stack.append(prev_focus)
	if not _modal_stack.is_empty():
		var prev_modal: Control = _modal_stack.back() as Control
		if is_instance_valid(prev_modal):
			prev_modal.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	else:
		_set_scene_focus_enabled(get_tree().current_scene, false)

	modal.process_mode = Node.PROCESS_MODE_ALWAYS
	modal.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	_overlay_layer.add_child(modal)
	_overlay_layer.move_child(_fade_rect, -1)
	_modal_stack.append(modal)
	if pause_tree:
		get_tree().paused = true


func pop_modal(modal: Control) -> void:
	var prev_focus: Control = null
	var idx: int = _modal_stack.find(modal)
	if idx >= 0:
		_modal_stack.remove_at(idx)
		if idx < _modal_focus_stack.size():
			prev_focus = _modal_focus_stack[idx]
			_modal_focus_stack.remove_at(idx)
	if is_instance_valid(modal):
		modal.queue_free()

	if _modal_stack.is_empty():
		get_tree().paused = false
		_set_scene_focus_enabled(get_tree().current_scene, true)
	else:
		var top: Control = _modal_stack.back() as Control
		if is_instance_valid(top):
			top.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED

	if is_instance_valid(prev_focus) and prev_focus.is_visible_in_tree() and prev_focus.get_focus_mode_with_override() != Control.FOCUS_NONE:
		prev_focus.grab_focus()


func get_top_modal() -> Control:
	if _modal_stack.is_empty():
		return null
	return _modal_stack.back() as Control


func has_modals() -> bool:
	return not _modal_stack.is_empty()


func clear_modals() -> void:
	for modal in _modal_stack:
		if is_instance_valid(modal):
			modal.queue_free()
	_modal_stack.clear()
	_modal_focus_stack.clear()
	_set_scene_focus_enabled(get_tree().current_scene, true)
	get_tree().paused = false


func _set_scene_focus_enabled(node: Node, enabled: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		(node as Control).focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if enabled else Control.FOCUS_BEHAVIOR_DISABLED
		return
	for child in node.get_children():
		_set_scene_focus_enabled(child, enabled)
