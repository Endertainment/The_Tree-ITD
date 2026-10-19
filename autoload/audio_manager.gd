extends Node
## Owns the three audio buses, the music player and the SFX/UI voice pools.
##
## Streams are loaded from `res://assets/audio/` at startup and addressed by
## file basename (`play_sfx("hit")`). Gameplay sounds play on the SFX bus, UI
## sounds on the UI bus, so the SFX slider never silences button feedback.
## Music ducks by `DUCK_DB` while the tree is paused and restores on resume.

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const UI_BUS := "UI"
const BUS_NAMES := [MUSIC_BUS, SFX_BUS, UI_BUS]
const SILENCE_DB := -60.0
const SFX_VOICES := 8
const UI_VOICES := 4
const DUCK_DB := -6.0
const CROSSFADE_SECONDS := 0.4
const SFX_DIR := "res://assets/audio/sfx"
const MUSIC_DIR := "res://assets/audio/music"
const DEFAULT_MUSIC := "grove_loop"
## Names used by earlier stages mapped onto the generated placeholder set.
const ALIASES := {
	"ui_click": "ui_tap",
	"tower_fire": "arrow",
	"boss_summon": "build",
}

## Mute everything while the app is in the background (settings toggle).
var mute_when_unfocused := true

var _music: AudioStreamPlayer
var _sfx_voices: Array[AudioStreamPlayer] = []
var _ui_voices: Array[AudioStreamPlayer] = []
var _library: Dictionary = {}
var _music_library: Dictionary = {}
var _volume_linear: Dictionary = {}
var _sfx_cursor := 0
var _ui_cursor := 0
var _music_tween: Tween
var _ducked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_music = AudioStreamPlayer.new()
	_music.name = "MusicPlayer"
	_music.bus = MUSIC_BUS
	add_child(_music)
	for index in SFX_VOICES:
		_sfx_voices.append(_make_voice("SfxVoice%d" % index, SFX_BUS))
	for index in UI_VOICES:
		_ui_voices.append(_make_voice("UiVoice%d" % index, UI_BUS))
	_load_libraries()
	apply_settings()
	play_default_music(0.0)


func _process(_delta: float) -> void:
	refresh_pause_duck()


func _exit_tree() -> void:
	stop_all_sfx()
	if _music != null:
		# Destroy the player eagerly: a looping playback that survives into
		# resource teardown is reported as a leak at exit.
		_music.stop()
		_music.stream = null
		if _music.get_parent() == self:
			remove_child(_music)
		_music.free()
		_music = null
	_library.clear()
	_music_library.clear()


## Applies music/sfx volumes and the focus-mute toggle from GameState.
func apply_settings() -> void:
	_set_bus_linear(MUSIC_BUS, float(GameState.get_setting("music", 0.8)))
	_set_bus_linear(SFX_BUS, float(GameState.get_setting("sfx", 1.0)))
	_set_bus_linear(UI_BUS, float(GameState.get_setting("sfx", 1.0)))
	mute_when_unfocused = bool(GameState.get_setting("mute_on_focus_loss", true))


## Re-reads the paused state and applies or removes the music duck.
func refresh_pause_duck() -> void:
	if not is_inside_tree():
		return
	var paused_now := get_tree().paused
	if paused_now == _ducked:
		return
	_ducked = paused_now
	_apply_bus(MUSIC_BUS)


## True while the music bus carries the pause duck.
func is_ducked() -> bool:
	return _ducked


## Current duck offset in dB (0 when running).
func get_duck_offset_db() -> float:
	return DUCK_DB if _ducked else 0.0


## Crossfades to `stream`. Re-calling with the same stream is a no-op.
func play_music(stream: AudioStream, fade := CROSSFADE_SECONDS) -> void:
	if stream == null:
		return
	if _music.stream == stream and _music.playing:
		return
	_kill_music_tween()
	if _music.playing and fade > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", SILENCE_DB, fade)
		await _music_tween.finished
	_kill_music_tween()
	_music.stream = stream
	_music.volume_db = SILENCE_DB
	_music.play()
	if fade > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", 0.0, fade)
	else:
		_music.volume_db = 0.0


## Starts the placeholder background loop.
func play_default_music(fade := CROSSFADE_SECONDS) -> void:
	var stream: AudioStream = _music_library.get(DEFAULT_MUSIC, null)
	if stream == null:
		return
	play_music(stream, fade)


## Fades the current track out and stops it.
func stop_music(fade := CROSSFADE_SECONDS) -> void:
	if not _music.playing:
		return
	_kill_music_tween()
	if fade > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", SILENCE_DB, fade)
		await _music_tween.finished
	_kill_music_tween()
	_music.stop()
	_music.stream = null


## Plays a gameplay sound from an id or a stream. Unknown ids are ignored.
func play_sfx(source: Variant) -> void:
	var stream := _resolve_stream(source)
	if stream == null:
		return
	_play_on(_sfx_voices, stream, _sfx_cursor)
	_sfx_cursor = (_sfx_cursor + 1) % maxi(1, _sfx_voices.size())


## Plays a UI sound from an id or a stream on the UI bus.
func play_ui(source: Variant) -> void:
	var stream := _resolve_stream(source)
	if stream == null:
		return
	# Every confirmed UI action also gives a light haptic tick on mobile.
	Haptics.tap()
	_play_on(_ui_voices, stream, _ui_cursor)
	_ui_cursor = (_ui_cursor + 1) % maxi(1, _ui_voices.size())


## Stops every pooled voice so no sound outlives its scene.
func stop_all_sfx() -> void:
	for voice: AudioStreamPlayer in _sfx_voices:
		voice.stop()
	for voice: AudioStreamPlayer in _ui_voices:
		voice.stop()


## Sets a bus volume in linear 0..1 space and persists it in settings.
func set_bus_volume(bus_name: String, linear: float) -> void:
	var value := clampf(linear, 0.0, 1.0)
	_set_bus_linear(bus_name, value)
	match bus_name:
		MUSIC_BUS:
			GameState.set_setting("music", value)
		SFX_BUS, UI_BUS:
			GameState.set_setting("sfx", value)
		_:
			pass


## Returns a bus volume in linear 0..1 space (0 when muted).
func get_bus_volume(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0 and AudioServer.is_bus_mute(index):
		return 0.0
	return float(_volume_linear.get(bus_name, 0.0))


## True when the sound library contains `id` (after alias resolution).
func has_sound(id: String) -> bool:
	return _resolve_id(id) in _library


## Returns the ids of every loaded sound effect.
func get_sfx_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _library:
		ids.append(id)
	ids.sort()
	return ids


## Registers a stream under an id so scenes can call `play_sfx("id")`.
func register_sfx(id: String, stream: AudioStream) -> void:
	_library[id] = stream


## Registers a stream under an id; the bus is chosen by the caller, not here.
func register_ui(id: String, stream: AudioStream) -> void:
	_library[id] = stream


func _notification(what: int) -> void:
	if not mute_when_unfocused:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			AudioServer.set_bus_mute(0, true)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			AudioServer.set_bus_mute(0, false)


func _load_libraries() -> void:
	_library.clear()
	_music_library.clear()
	var sfx_dir := DirAccess.open(SFX_DIR)
	if sfx_dir == null:
		push_warning("[AudioManager] missing %s; run tools/gen_placeholder_sfx.gd" % SFX_DIR)
	else:
		for file_name: String in sfx_dir.get_files():
			if not file_name.ends_with(".wav"):
				continue
			var stream := load(SFX_DIR + "/" + file_name) as AudioStream
			if stream == null:
				continue
			if stream is AudioStreamWAV:
				(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
			_library[file_name.get_basename()] = stream
	var music_dir := DirAccess.open(MUSIC_DIR)
	if music_dir == null:
		push_warning("[AudioManager] missing %s" % MUSIC_DIR)
		return
	for file_name: String in music_dir.get_files():
		var extension := file_name.get_extension().to_lower()
		if extension != "wav" and extension != "ogg":
			continue
		var music := load(MUSIC_DIR + "/" + file_name) as AudioStream
		if music == null:
			continue
		_enable_loop(music)
		_music_library[file_name.get_basename()] = music


func _enable_loop(stream: AudioStream) -> void:
	if not stream is AudioStreamWAV:
		return
	var wav := stream as AudioStreamWAV
	if wav.stereo or wav.format != AudioStreamWAV.FORMAT_16_BITS:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = wav.data.size() / 2


func _resolve_id(id: String) -> String:
	if _library.has(id):
		return id
	var alias: String = ALIASES.get(id, "")
	if alias != "" and _library.has(alias):
		return alias
	return id


func _resolve_stream(source: Variant) -> AudioStream:
	if source is AudioStream:
		return source as AudioStream
	if source is String or source is StringName:
		var id := _resolve_id(str(source))
		if _library.has(id):
			return _library[id] as AudioStream
		return _music_library.get(id, null) as AudioStream
	return null


func _ensure_buses() -> void:
	for bus_name: String in BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func _make_voice(voice_name: String, bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = voice_name
	player.bus = bus_name
	add_child(player)
	return player


func _play_on(voices: Array[AudioStreamPlayer], stream: AudioStream, cursor: int) -> void:
	if voices.is_empty():
		return
	var player := voices[cursor % voices.size()]
	player.stream = stream
	player.play()


func _set_bus_linear(bus_name: String, linear: float) -> void:
	_volume_linear[bus_name] = clampf(linear, 0.0, 1.0)
	_apply_bus(bus_name)


func _apply_bus(bus_name: String) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var linear := float(_volume_linear.get(bus_name, 0.0))
	var offset := DUCK_DB if (bus_name == MUSIC_BUS and _ducked) else 0.0
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)) + offset)


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null
