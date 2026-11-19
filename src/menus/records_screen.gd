extends Control

## Hall of Fame screen displaying top 10 Workday and Arcade records.

@onready var _title_label: Label = $TitleLabel
@onready var _workday_title: Label = $WorkdayTitle
@onready var _arcade_title: Label = $ArcadeTitle
@onready var _workday_list: VBoxContainer = $WorkdayList
@onready var _arcade_list: VBoxContainer = $ArcadeList
@onready var _btn_back: Button = $BtnBack


func _ready() -> void:
	_title_label.text = I18n.t("records_title")
	_workday_title.text = I18n.t("btn_workday")
	_arcade_title.text = I18n.t("btn_arcade")

	_btn_back.text = I18n.t("btn_back")
	_btn_back.pressed.connect(_on_back)
	_btn_back.grab_focus()

	var records: Dictionary = SaveManager.load_slot("records", {"workday": [], "arcade": []})
	_populate_list(_workday_list, records.get("workday", []) as Array, "records_workday_format")
	_populate_list(_arcade_list, records.get("arcade", []) as Array, "records_arcade_format")


func _populate_list(container: VBoxContainer, entries: Array, fmt_key: String) -> void:
	for i in entries.size():
		var rec: Dictionary = entries[i] as Dictionary
		var lbl: Label = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = I18n.t(fmt_key, {
			"i": i + 1,
			"name": str(rec.get("name", "Unknown")),
			"score": int(rec.get("score", 0)),
		})
		container.add_child(lbl)


func _unhandled_input(event: InputEvent) -> void:
	if GameFlow.has_modals():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_on_back()


func _on_back() -> void:
	AudioManager.play_sfx("press")
	GameFlow.change_scene("res://src/menus/title_screen.tscn", 0.5, 0.5)
