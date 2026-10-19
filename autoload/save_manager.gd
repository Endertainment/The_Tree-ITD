extends Node
## File persistence only: load, migrate, atomic write, backup, corruption recovery.
##
## This singleton owns no game data. `GameState` passes in plain dictionaries
## and receives plain dictionaries back, which keeps autoload order irrelevant.

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.tmp"
const BAK_PATH := "user://save.bak"
const CORRUPT_PATH := "user://save.corrupt"
const SAVE_FILES := ["save.json", "save.tmp", "save.bak", "save.corrupt"]
const DEBOUNCE_SECONDS := 0.5

var _timer: Timer
var _pending: Dictionary = {}
var _has_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.name = "SaveDebounce"
	_timer.one_shot = true
	_timer.wait_time = DEBOUNCE_SECONDS
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.timeout.connect(_on_debounce_timeout)
	add_child(_timer)


## Reads, migrates and validates the save without touching GameState.
## Missing file, unreadable JSON and a broken backup all degrade to defaults.
func load_game() -> Dictionary:
	if FileAccess.file_exists(SAVE_PATH):
		var primary := _read_json(SAVE_PATH)
		if not primary.is_empty():
			return _prepare(primary)
		push_warning("[SaveManager] save.json is unreadable; trying save.bak")
		_keep_corrupt_copy()
	var backup := _read_json(BAK_PATH)
	if not backup.is_empty():
		push_warning("[SaveManager] recovered the profile from save.bak")
		return _prepare(backup)
	return _prepare(SaveDefaults.create())


## Queues a debounced write (at most one write per SAVE_DEBOUNCE_SECONDS).
func save_game(data: Dictionary) -> void:
	if data.is_empty():
		return
	_pending = data.duplicate(true)
	_has_pending = true
	if _timer != null:
		_timer.start()


## Writes immediately. Used on pause, quit, purchases and by the tests.
## With no argument it flushes the last queued snapshot.
func save_now(data: Dictionary = {}) -> void:
	if not data.is_empty():
		_pending = data.duplicate(true)
		_has_pending = true
	_flush()


## Deletes every save file and writes a fresh default profile.
func reset_progress() -> void:
	if _timer != null:
		_timer.stop()
	_has_pending = false
	_pending = {}
	for file_name: String in SAVE_FILES:
		var path := "user://" + file_name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_write_atomic(SaveDefaults.create())


## Returns the absolute user:// path of the main save file.
func get_save_path() -> String:
	return SAVE_PATH


## True when a main save file exists on disk.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_flush()


func _on_debounce_timeout() -> void:
	_flush()


func _flush() -> void:
	if _timer != null:
		_timer.stop()
	if not _has_pending:
		return
	_write_atomic(_pending)
	_has_pending = false
	_pending = {}


func _prepare(data: Dictionary) -> Dictionary:
	var migrated := SaveMigrations.migrate(data)
	var merged := _merge_missing(SaveDefaults.create(), migrated)
	merged["last_seen"] = int(Time.get_unix_time_from_system())
	return merged


func _merge_missing(defaults: Dictionary, incoming: Dictionary) -> Dictionary:
	var out: Dictionary = incoming.duplicate(true)
	for key: Variant in defaults:
		if not out.has(key):
			out[key] = defaults[key]
			continue
		var default_value: Variant = defaults[key]
		var incoming_value: Variant = out[key]
		if default_value is Dictionary and incoming_value is Dictionary:
			out[key] = _merge_missing(default_value, incoming_value)
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	# JSON.parse() reports through its return code instead of pushing an error,
	# so a corrupt save does not look like an engine failure in the log.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func _write_atomic(data: Dictionary) -> void:
	var json := JSON.stringify(data, "\t")
	var round_trip: Variant = JSON.parse_string(json)
	if not round_trip is Dictionary:
		push_error("[SaveManager] refusing to write invalid JSON")
		return
	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] cannot open %s for writing" % TMP_PATH)
		return
	file.store_string(json)
	file.flush()
	file.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("[SaveManager] cannot open user://")
		return
	_backup_current()
	var err := dir.rename("save.tmp", "save.json")
	if err != OK:
		# Windows may refuse to rename over an existing file; drop it and retry.
		DirAccess.remove_absolute(SAVE_PATH)
		err = dir.rename("save.tmp", "save.json")
	if err != OK:
		push_warning("[SaveManager] rename failed (%d); falling back to copy" % err)
		err = _copy_file(TMP_PATH, SAVE_PATH)
		if err == OK:
			DirAccess.remove_absolute(TMP_PATH)
		else:
			push_error("[SaveManager] save failed (%d)" % err)


func _backup_current() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	if FileAccess.file_exists(BAK_PATH):
		DirAccess.remove_absolute(BAK_PATH)
	var err := _copy_file(SAVE_PATH, BAK_PATH)
	if err != OK:
		push_warning("[SaveManager] could not refresh save.bak (%d)" % err)


func _keep_corrupt_copy() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	if FileAccess.file_exists(CORRUPT_PATH):
		DirAccess.remove_absolute(CORRUPT_PATH)
	_copy_file(SAVE_PATH, CORRUPT_PATH)


## Copies a `user://` file. DirAccess.copy() would resolve relative paths
## against the process working directory, so this uses FileAccess explicitly.
func _copy_file(from_path: String, to_path: String) -> Error:
	var source := FileAccess.open(from_path, FileAccess.READ)
	if source == null:
		return FileAccess.get_open_error()
	var target := FileAccess.open(to_path, FileAccess.WRITE)
	if target == null:
		source.close()
		return FileAccess.get_open_error()
	target.store_buffer(source.get_buffer(source.get_length()))
	target.flush()
	target.close()
	source.close()
	return OK
