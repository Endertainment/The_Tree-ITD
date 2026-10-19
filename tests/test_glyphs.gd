extends Node
## Headless font-coverage test for the UI theme.
##
## Renders the Ukrainian alphabet and every non-ASCII character used by the
## `uk` column of `strings.csv`, then asks the theme font whether it can draw
## each one. A missing glyph is a tofu box on device, so it fails the suite.
##
## Run with:
##   godot --headless --path <project> res://tests/TestGlyphs.tscn

const REQUIRED := "ЇїЄєҐґІі—"
const ALPHABET := "АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯабвгґдеєжзиіїйклмнопрстуфхцчшщьюя"
const PROBE_KEY := "TUTORIAL_BUILD"
const CSV_PATH := "res://localization/strings.csv"

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	var label := Label.new()
	label.text = ALPHABET + REQUIRED
	add_child(label)
	await get_tree().process_frame

	_section("theme font")
	var font := label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	_check(font != null, "a UI font is available")

	_section("required glyphs")
	for index in REQUIRED.length():
		var glyph := REQUIRED[index]
		_check(
			font != null and font.has_char(glyph.unicode_at(0)),
			"font renders '%s' (U+%04X)" % [glyph, glyph.unicode_at(0)]
		)

	_section("alphabet")
	var missing := ""
	if font != null:
		for index in ALPHABET.length():
			var glyph := ALPHABET[index]
			if not font.has_char(glyph.unicode_at(0)):
				missing += glyph
	_check(missing.is_empty(), "every Ukrainian letter renders (missing: '%s')" % missing)

	_section("localized strings")
	var localized := _localized_characters()
	_check(localized.length() > 0, "strings.csv has Ukrainian text to check")
	var unrenderable := ""
	if font != null:
		for index in localized.length():
			var glyph := localized[index]
			if not font.has_char(glyph.unicode_at(0)):
				unrenderable += glyph
	_check(unrenderable.is_empty(), "every character in the uk column renders (missing: '%s')" % unrenderable)

	_section("runtime lookup")
	var previous := Loc.get_locale()
	Loc.set_locale("uk")
	var uk_text := Loc.t_key(PROBE_KEY)
	_check(uk_text != PROBE_KEY, "uk lookup returns text, not the key")
	_check(uk_text.contains("м"), "uk lookup returns Cyrillic")
	Loc.set_locale("en")
	var en_text := Loc.t_key(PROBE_KEY)
	_check(en_text != uk_text, "en and uk differ for %s" % PROBE_KEY)
	Loc.set_locale(previous)

	_section("export path")
	# Exported builds ship compiled .translation resources, not the CSV source.
	# Loc falls back to these, so they must carry the same text.
	# `OptimizedTranslation` cannot enumerate its messages, so freshness is
	# checked by looking up keys added late in the CSV.
	for code: String in ["en", "uk"]:
		var compiled := load("res://localization/strings.%s.translation" % code) as Translation
		_check(compiled != null, "compiled %s translation loads" % code)
		if compiled == null:
			continue
		for key: String in [PROBE_KEY, "TOWER_TAB_LEVEL", "SET_DAMAGE_NUMBERS", "DEV_BENCH_RESULT"]:
			_check(
				compiled.get_message(key) != "",
				"compiled %s translation carries %s" % [code, key]
			)

	_finish()


## Unique non-ASCII characters used by the Ukrainian column.
func _localized_characters() -> String:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		return ""
	var header := file.get_csv_line()
	var uk_column := -1
	for index in header.size():
		if header[index].strip_edges() == "uk":
			uk_column = index
			break
	if uk_column < 0:
		file.close()
		return ""
	var seen := {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() <= uk_column:
			continue
		var text := row[uk_column]
		for index in text.length():
			var glyph := text[index]
			if glyph.unicode_at(0) < 128:
				continue
			seen[glyph] = true
	file.close()
	var characters := ""
	for glyph: String in seen:
		characters += glyph
	return characters


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL GLYPH TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("GLYPH TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
	get_tree().quit(1)


func _section(title: String) -> void:
	print("")
	print("== %s ==" % title)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures.append(message)
		print("  FAIL ", message)
