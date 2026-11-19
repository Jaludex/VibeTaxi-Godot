class_name GameOverModal
extends Control

## Game Over modal displaying failure reason, delayed RANK reveal, and transition to NewRecord/Title.

@onready var _dim: ColorRect = $Dim
@onready var _panel: Panel = $Panel
@onready var _title_label: Label = $Panel/TitleLabel
@onready var _typewriter: TypewriterBox = $Panel/TypewriterBox
@onready var _rank_value: Label = $Panel/RankValue
@onready var _rank_label: Label = $Panel/RankLabel
@onready var _btn_ok: Button = $Panel/BtnOk

var _reason: String = ""
var _mode: String = ""
var _score: float = 0.0
var _record_data: Dictionary = {}
var _rank_revealed: bool = false
var _is_exiting: bool = false


func setup(params: Dictionary) -> void:
	_reason = str(params.get("reason", ""))
	_mode = str(params.get("mode", ""))
	_score = float(params.get("score", 0.0))
	_record_data = params.get("record_data", {}) as Dictionary


func _ready() -> void:
	AudioManager.play_sfx("game_over")

	_title_label.text = I18n.t("game_over_title")
	_rank_label.text = I18n.t("game_over_rank_label")
	_typewriter.set_box_text(_reason if not _reason.is_empty() else "OK")
	_btn_ok.text = I18n.t("btn_ok")
	_btn_ok.pressed.connect(_on_ok_pressed)
	_btn_ok.grab_focus()

	_rank_value.modulate.a = 0.0

	var chosen_rank: Dictionary = _compute_rank()
	if not chosen_rank.is_empty():
		_rank_value.text = str(chosen_rank["name"])
		_rank_value.add_theme_color_override("font_color", chosen_rank["color"] as Color)

	_dim.color.a = 0.0
	_panel.position.y = -220.0
	var target_y: float = (get_viewport_rect().size.y - _panel.size.y) * 0.5

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 180.0 / 255.0, 0.3)
	tween.tween_property(_panel, "position:y", target_y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if not chosen_rank.is_empty():
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if not is_instance_valid(self):
				return
			var snd: String = str(chosen_rank.get("sound", ""))
			if not snd.is_empty():
				AudioManager.play_sfx(snd)
			var r_tween: Tween = create_tween()
			r_tween.tween_property(_rank_value, "modulate:a", 1.0, 0.4)
			r_tween.tween_callback(func() -> void: _rank_revealed = true)
		)
	else:
		_rank_revealed = true


func _compute_rank() -> Dictionary:
	if _mode.is_empty():
		return {}
	var best: Dictionary = GameConstants.RANKS[0]
	for r in GameConstants.RANKS:
		if _mode == "workday" and _score >= float(r["workday_min"]):
			best = r
		elif _mode == "arcade" and _score >= float(r["arcade_min"]):
			best = r
	return best


func _on_ok_pressed() -> void:
	if _is_exiting:
		return
	if _typewriter.is_typing or _typewriter.has_next_page():
		_typewriter.advance()
		return
	if not GameConstants.ALLOW_GAMEOVER_SKIP and not _rank_revealed:
		return

	_is_exiting = true
	AudioManager.play_sfx("press")

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.0, 0.3)
	tween.tween_property(_panel, "position:y", -220.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		if not _record_data.is_empty():
			var nr: NewRecordModal = (load("res://src/menus/new_record.tscn") as PackedScene).instantiate() as NewRecordModal
			nr.setup(_record_data)
			GameFlow.pop_modal(self)
			GameFlow.push_modal(nr, true)
		else:
			GameFlow.change_scene("res://src/menus/title_screen.tscn", 0.5, 0.5)
	)
