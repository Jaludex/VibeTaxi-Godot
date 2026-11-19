extends Node

## Atomic JSON save/load manager writing to user://saves/<slot>.json.

var save_dir: String = "user://saves"


func _ready() -> void:
	_ensure_dir()


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)


func _slot_path(slot: String) -> String:
	return "%s/%s.json" % [save_dir, slot]


func exists(slot: String) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func save_slot(slot: String, data: Dictionary) -> bool:
	_ensure_dir()
	var path: String = _slot_path(slot)
	var tmp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot open %s for writing" % tmp_path)
		return false

	var envelope: Dictionary = {
		"version": 1,
		"updated_at": Time.get_unix_time_from_system(),
		"data": data,
	}
	file.store_string(JSON.stringify(envelope, "\t"))
	file.close()

	var err: Error = DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		var direct: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if direct == null:
			return false
		direct.store_string(JSON.stringify(envelope, "\t"))
		direct.close()
		DirAccess.remove_absolute(tmp_path)
	return true


func load_slot(slot: String, default_value: Dictionary = {}) -> Dictionary:
	var path: String = _slot_path(slot)
	if not FileAccess.file_exists(path):
		return default_value.duplicate(true)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return default_value.duplicate(true)

	var raw: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		var dict: Dictionary = parsed as Dictionary
		if dict.has("data") and dict["data"] is Dictionary:
			return (dict["data"] as Dictionary).duplicate(true)
		return dict.duplicate(true)
	return default_value.duplicate(true)


func delete_slot(slot: String) -> void:
	var path: String = _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
