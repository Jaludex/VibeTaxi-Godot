class_name TypewriterBox
extends Control

## Paginated typewriter text display with character-by-character reveal and bleep SFX.

signal finished_typing
signal page_changed(page_idx: int, total_pages: int)
signal completed_all_pages

@export var chars_per_second: float = 40.0
@export var lines_per_page: int = 3
@export var font_size: int = 14
@export var line_spacing: int = -2
@export var play_bleeps: bool = true

var _label: Label
var _pages: Array[String] = []
var _current_page: int = 0
var _visible_chars: float = 0.0
var _last_bleep_count: int = 0
var is_typing: bool = false


func _ready() -> void:
	_label = get_node_or_null("TextLabel") as Label
	if _label == null:
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.add_theme_color_override("font_color", Color.WHITE)
		_label.add_theme_font_size_override("font_size", font_size)
		_label.add_theme_constant_override("line_spacing", line_spacing)
		add_child(_label)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.clip_text = true


func set_box_text(raw_text: String) -> float:
	if _label == null:
		_ready()
	_pages = _paginate_text(raw_text)
	_current_page = 0
	_show_current_page()
	return estimate_total_typing_time()


func has_next_page() -> bool:
	return _current_page < _pages.size() - 1


func next_page() -> bool:
	if has_next_page():
		_current_page += 1
		_show_current_page()
		page_changed.emit(_current_page, _pages.size())
		return true
	completed_all_pages.emit()
	return false


func advance() -> void:
	if is_typing:
		_visible_chars = float(_label.text.length())
		_label.visible_characters = -1
		is_typing = false
		finished_typing.emit()
	elif has_next_page():
		next_page()
	else:
		completed_all_pages.emit()


func estimate_total_typing_time() -> float:
	var total: float = 0.0
	for i in _pages.size():
		total += float(_pages[i].length()) / maxf(1.0, chars_per_second)
		if i < _pages.size() - 1:
			total += GameConstants.PASSENGER_NEXT_PAGE_TIME
	return total


func _show_current_page() -> void:
	var text: String = _pages[_current_page] if not _pages.is_empty() else ""
	_label.text = text
	_label.visible_characters = 0
	_visible_chars = 0.0
	_last_bleep_count = 0
	is_typing = not text.is_empty()
	if not is_typing:
		finished_typing.emit()


func _process(delta: float) -> void:
	if not is_typing or _label == null:
		return
	var total_len: int = _label.text.length()
	_visible_chars += chars_per_second * delta
	var target_count: int = mini(total_len, int(_visible_chars))
	if target_count > _last_bleep_count:
		if play_bleeps and target_count <= total_len:
			var ch: String = _label.text[target_count - 1]
			if ch != " " and ch != "\n" and ch != "\t":
				AudioManager.play_sfx("bleep%d" % randi_range(1, 5), 0.35)
		_last_bleep_count = target_count
		_label.visible_characters = target_count

	if target_count >= total_len:
		_label.visible_characters = -1
		is_typing = false
		finished_typing.emit()


func _paginate_text(raw_text: String) -> Array[String]:
	var font: Font = _label.get_theme_font(&"font") if _label != null else ThemeDB.fallback_font
	if font == null:
		font = ThemeDB.fallback_font
	var measure_size: int = _label.get_theme_font_size(&"font_size") if _label != null else font_size
	var max_width: float = maxf(60.0, size.x - 6.0)
	var wrapped_lines: Array[String] = []

	for paragraph in raw_text.split("\n"):
		if paragraph.is_empty():
			wrapped_lines.append("")
			continue
		var current_line: String = ""
		for word in paragraph.split(" "):
			var candidate: String = word if current_line.is_empty() else (current_line + " " + word)
			var w: float = font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, measure_size).x
			if w <= max_width or current_line.is_empty():
				current_line = candidate
			else:
				wrapped_lines.append(current_line)
				current_line = word
		if not current_line.is_empty():
			wrapped_lines.append(current_line)

	if wrapped_lines.is_empty():
		return [""]

	var pages: Array[String] = []
	var idx: int = 0
	while idx < wrapped_lines.size():
		var end_idx: int = mini(idx + lines_per_page, wrapped_lines.size())
		var chunk: PackedStringArray = PackedStringArray()
		for j in range(idx, end_idx):
			chunk.append(wrapped_lines[j])
		pages.append("\n".join(chunk))
		idx = end_idx
	return pages
