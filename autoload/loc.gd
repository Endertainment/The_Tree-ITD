extends Node
## Localization: loads `res://localization/strings.csv` into runtime Translation
## objects, switches locale and formats numbers.
##
## The CSV is parsed directly instead of relying on the editor import pipeline,
## so a fresh clone runs correctly in `--headless` mode without an import pass.

const CSV_PATH := "res://localization/strings.csv"
const FALLBACK_LOCALE := "en"
const THIN_SPACE := "\u2009"

var _translations: Dictionary = {}
var _locales: PackedStringArray = []
var _current := FALLBACK_LOCALE


func _ready() -> void:
	_load_csv()
	if _locales.is_empty():
		_load_translation_resources()
	TranslationServer.set_locale(FALLBACK_LOCALE)
	_current = FALLBACK_LOCALE


## Switches locale, falls back to `en` and persists the choice.
func set_locale(locale: String) -> void:
	var target := locale
	if not _locales.has(target):
		push_warning("[Loc] unsupported locale '%s', using '%s'" % [locale, FALLBACK_LOCALE])
		target = FALLBACK_LOCALE
	_current = target
	TranslationServer.set_locale(target)
	if GameState != null:
		GameState.set_setting("locale", target)


## Returns the active two-letter locale code.
func get_locale() -> String:
	return _current


## Returns every locale code present in the CSV header.
func get_available_locales() -> PackedStringArray:
	return _locales.duplicate()


## Translates `key` and substitutes `{name}` placeholders from `args`.
func t_key(key: String, args: Dictionary = {}) -> String:
	var text := String(tr(key))
	if args.is_empty():
		return text
	for arg_key: Variant in args:
		text = text.replace("{%s}" % str(arg_key), str(args[arg_key]))
	return text


## Formats an integer with thin-space thousands separators: 12500 -> "12 500".
func format_number(value: int) -> String:
	var negative := value < 0
	var digits := str(absi(value))
	var grouped := ""
	var count := 0
	for index in range(digits.length() - 1, -1, -1):
		grouped = digits[index] + grouped
		count += 1
		if count % 3 == 0 and index > 0:
			grouped = THIN_SPACE + grouped
	if negative:
		return "-" + grouped
	return grouped


func _load_csv() -> void:
	for locale: String in _translations:
		TranslationServer.remove_translation(_translations[locale])
	_translations.clear()
	_locales.clear()

	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_error("[Loc] cannot open %s" % CSV_PATH)
		return

	var header := file.get_csv_line()
	if header.size() < 2:
		push_error("[Loc] %s has no locale columns" % CSV_PATH)
		file.close()
		return

	var columns: Array[String] = []
	for index in range(1, header.size()):
		var code := header[index].strip_edges()
		if code.is_empty():
			continue
		columns.append(code)
		_locales.append(code)
		var translation := Translation.new()
		translation.locale = code
		_translations[code] = translation

	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty():
			continue
		var key := row[0].strip_edges()
		if key.is_empty() or key == "keys":
			continue
		for index in columns.size():
			var cell_index := index + 1
			if cell_index >= row.size():
				break
			var value: String = row[cell_index]
			if value.is_empty():
				continue
			var translation: Translation = _translations[columns[index]]
			translation.add_message(key, value)
	file.close()

	for code: String in _translations:
		TranslationServer.add_translation(_translations[code])


## Export fallback. A packaged build contains the compiled `.translation`
## resources but not the raw CSV, because the CSV is an import source file.
func _load_translation_resources() -> void:
	var dir := DirAccess.open("res://localization")
	if dir == null:
		push_error("[Loc] no localization data found")
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".translation"):
			continue
		var translation := load("res://localization/" + file_name) as Translation
		if translation == null:
			continue
		_translations[translation.locale] = translation
		_locales.append(translation.locale)
		TranslationServer.add_translation(translation)
	if _locales.is_empty():
		push_error("[Loc] no translations available")
