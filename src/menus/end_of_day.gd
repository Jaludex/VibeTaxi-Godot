class_name EndOfDayModal
extends Control

## End-of-day Workday summary allowing taxi repairs, saving & exiting, or starting the next shift.

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _day_label: Label = $Panel/DayLabel
@onready var _money_label: Label = $Panel/MoneyLabel
@onready var _btn_repair: Button = $Panel/BtnRepair
@onready var _health_bar: ProgressBar = $Panel/HealthBar
@onready var _btn_exit: Button = $Panel/BtnExit
@onready var _btn_save_exit: Button = $Panel/BtnSaveExit
@onready var _btn_continue: Button = $Panel/BtnContinue

var _money: float = 0.0
var _health: float = 140.0
var _max_health: float = GameConstants.TAXI_MAX_HEALTH
var _day: int = 1
var _is_loaded_run: bool = false
var _fill_style: StyleBoxFlat


func setup(params: Dictionary) -> void:
	_money = float(params.get("money", 0.0))
	_health = float(params.get("health", _max_health))
	_day = int(params.get("day", 1))
	_is_loaded_run = bool(params.get("is_loaded_run", false))


func _ready() -> void:
	AudioManager.play_sfx("win")

	_fill_style = StyleBoxFlat.new()
	_health_bar.add_theme_stylebox_override("fill", _fill_style)

	_day_label.text = I18n.t("end_of_day_title_format", {"day": _day})
	_money_label.text = I18n.t("end_of_day_money", {"money": "%.2f" % _money})
	_money_label.add_theme_color_override("font_color", GameConstants.UI_GREEN)
	_btn_repair.text = I18n.t("btn_repair_taxi_cost", {"cost": "%.0f" % GameConstants.REPAIR_COST})
	_btn_exit.text = I18n.t("btn_exit_menu")
	_btn_save_exit.text = I18n.t("btn_save_quit")
	_btn_continue.text = I18n.t("btn_continue")

	_btn_repair.pressed.connect(_on_repair)
	_btn_exit.pressed.connect(_on_exit)
	_btn_save_exit.pressed.connect(_on_save_exit)
	_btn_continue.pressed.connect(_on_continue)

	_refresh_health_ui()

	_panel.visible = false
	_dim.color.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_dim, "color:a", 180.0 / 255.0, 1.0)
	tween.tween_callback(func() -> void:
		_panel.visible = true
		_btn_continue.grab_focus()
	)


func _refresh_health_ui() -> void:
	_money_label.text = I18n.t("end_of_day_money", {"money": "%.2f" % _money})
	_health_bar.max_value = _max_health
	_health_bar.value = _health
	var pct: float = _health / maxf(1.0, _max_health)
	if pct <= 0.2:
		_fill_style.bg_color = Color.RED
	elif pct <= 0.5:
		_fill_style.bg_color = Color.YELLOW
	else:
		_fill_style.bg_color = Color.GREEN
	_btn_repair.disabled = (_health >= _max_health or _money < GameConstants.REPAIR_COST)
	_btn_repair.focus_mode = Control.FOCUS_NONE if _btn_repair.disabled else Control.FOCUS_ALL


func _on_repair() -> void:
	if _health < _max_health and _money >= GameConstants.REPAIR_COST:
		AudioManager.play_sfx("fix")
		_money -= GameConstants.REPAIR_COST
		_health = _max_health
		_refresh_health_ui()


func _on_exit() -> void:
	AudioManager.play_sfx("press")
	GameFlow.change_scene("res://src/menus/title_screen.tscn", 0.5, 0.5)


func _on_save_exit() -> void:
	AudioManager.play_sfx("press")
	var execute_save: Callable = func() -> void:
		SaveManager.save_slot("workday_save", {
			"money": _money,
			"health": _health,
			"day": _day + 1,
		})
		GameFlow.change_scene("res://src/menus/title_screen.tscn", 0.5, 0.5)

	if not _is_loaded_run and SaveManager.exists("workday_save"):
		var confirm: ConfirmationBoxModal = (load("res://src/menus/confirmation_box.tscn") as PackedScene).instantiate() as ConfirmationBoxModal
		confirm.setup(I18n.t("confirm_overwrite"))
		confirm.confirmed.connect(execute_save)
		GameFlow.push_modal(confirm, true)
	else:
		execute_save.call()


func _on_continue() -> void:
	AudioManager.play_sfx("press")
	GameFlow.start_gameplay("workday", {
		"money": _money,
		"day": _day + 1,
		"taxi_health": _health,
		"is_loaded_run": _is_loaded_run,
	})
