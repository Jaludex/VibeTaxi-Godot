extends Node

## Thin wrapper around Godot's TranslationServer (CSV-backed) with parameterized format and random dialogue pools.

signal language_changed(lang_code: String)

const SUPPORTED_LOCALES: Array[String] = ["en", "es"]


func _ready() -> void:
	TranslationServer.set_locale(get_language())


func get_language() -> String:
	var lang: String = str(ConfigManager.get_value("language", ""))
	if lang in SUPPORTED_LOCALES:
		return lang
	return "en"


func set_language(lang_code: String) -> void:
	if not (lang_code in SUPPORTED_LOCALES):
		return
	TranslationServer.set_locale(lang_code)
	ConfigManager.set_value("language", lang_code, true)
	language_changed.emit(lang_code)


func get_available_languages() -> Array[String]:
	return SUPPORTED_LOCALES.duplicate()


func get_language_name(lang_code: String) -> String:
	var tr_obj: Translation = TranslationServer.get_translation_object(lang_code)
	if tr_obj != null:
		var msg: String = tr_obj.get_message(&"language_name")
		if not msg.is_empty():
			return msg
	return lang_code.to_upper()


func t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var translated: String = tr(key)
	if translated == key and not fallback.is_empty():
		translated = fallback
	if not params.is_empty():
		translated = translated.format(params)
	return translated


func pick_dialogue(category: String, subcategory: String = "", params: Dictionary = {}) -> String:
	var prefix: String = "dlg_%s_" % category if subcategory.is_empty() else "dlg_%s_%s_" % [category, subcategory]
	var pool: Array[String] = []
	var idx: int = 0
	while idx < 64:
		var k: String = prefix + str(idx)
		var msg: String = tr(k)
		if msg == k:
			break
		pool.append(msg)
		idx += 1
	if pool.is_empty():
		return ""
	var chosen: String = pool[randi() % pool.size()]
	if not params.is_empty():
		chosen = chosen.format(params)
	return chosen
