extends Control

## Opening splash screen displaying studio slides with fade-in/out and skip support.

const SLIDES: Array[Dictionary] = [
	{"text": "Whitebox Studio", "subtext": "Presents...", "hold": 1.5},
	{"text": "A game made with <3", "subtext": "and lots of coffee", "hold": 1.5},
]

const FADE_TIME: float = 0.8

@onready var _slide_box: VBoxContainer = $CenterContainer/SlideBox
@onready var _title_label: Label = $CenterContainer/SlideBox/TitleLabel
@onready var _sub_label: Label = $CenterContainer/SlideBox/SubLabel

var _finished: bool = false
var _tween: Tween = null


func _ready() -> void:
	_slide_box.modulate.a = 0.0
	_play_slide(0)


func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event.is_pressed() and not event.is_echo():
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
			_finish()


func _play_slide(index: int) -> void:
	if _finished:
		return
	if index >= SLIDES.size():
		_finish()
		return

	var slide: Dictionary = SLIDES[index]
	_title_label.text = str(slide["text"])
	_sub_label.text = str(slide["subtext"])
	_slide_box.modulate.a = 0.0

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(_slide_box, "modulate:a", 1.0, FADE_TIME)
	_tween.tween_interval(float(slide["hold"]))
	_tween.tween_property(_slide_box, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(_play_slide.bind(index + 1))


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _tween != null and _tween.is_valid():
		_tween.kill()

	if not ConfigManager.has_language_selected():
		var lang_scene: PackedScene = load("res://src/menus/language_selection.tscn") as PackedScene
		var lang_modal: LanguageSelectionModal = lang_scene.instantiate() as LanguageSelectionModal
		lang_modal.standalone_mode = true
		lang_modal.closed.connect(func() -> void:
			GameFlow.change_scene("res://src/menus/title_screen.tscn", 0.0, 0.8)
		)
		GameFlow.push_modal(lang_modal, false)
	else:
		GameFlow.change_scene("res://src/menus/title_screen.tscn", 0.0, 0.8)
