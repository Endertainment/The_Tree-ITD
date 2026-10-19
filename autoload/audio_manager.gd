extends Node
## Music / SFX / UI buses, volume persistence and simple voice pooling.
##
## Placeholder audio for now: the libraries are empty, so `play_sfx("id")` for an
## unknown id is a silent no-op. Stage 7 fills them.

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const UI_BUS := "UI"
const BUS_NAMES := [MUSIC_BUS, SFX_BUS, UI_BUS]
const SILENCE_DB := -60.0
const SFX_VOICES := 8
const UI_VOICES := 4

## Mute everything while the app is in the background. Menu defaults to false.
var mute_when_unfocused := false

var _music: AudioStreamPlayer
var _sfx_voices: Array[AudioStreamPlayer] = []
var _ui_voices: Array[AudioStreamPlayer] = []
var _sfx_library: Dictionary = {}
var _ui_library: Dictionary = {}
var _sfx_cursor := 0
var _ui_cursor := 0
var _music_tween: Tween


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


## Applies music/sfx volumes from GameState without writing them back.
func apply_settings() -> void:
	_set_bus_linear(MUSIC_BUS, float(GameState.get_setting("music", 0.8)))
	_set_bus_linear(SFX_BUS, float(GameState.get_setting("sfx", 1.0)))
	_set_bus_linear(UI_BUS, float(GameState.get_setting("sfx", 1.0)))


## Crossfades to `stream`. Re-calling with the same stream is a no-op.
func play_music(stream: AudioStream, fade := 0.4) -> void:
	if stream == null:
		return
	if _music.stream == stream and _music.playing:
		return
	_kill_music_tween()
	if _music.playing and fade > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", SILENCE_DB, fade)
		await _music_tween.finished
	_music.stream = stream
	_music.volume_db = SILENCE_DB
	_music.play()
	if fade > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", 0.0, fade)
	else:
		_music.volume_db = 0.0


## Fades the current track out and stops it.
func stop_music(fade := 0.4) -> void:
	if not _music.playing:
		return
	_kill_music_tween()
	if fade > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", SILENCE_DB, fade)
		await _music_tween.finished
	_music.stop()
	_music.stream = null


## Plays a sound effect from an id or a stream. Unknown ids are ignored.
func play_sfx(source: Variant) -> void:
	var stream := _resolve_stream(source, _sfx_library)
	if stream == null:
		return
	_play_on(_sfx_voices, stream, _sfx_cursor)
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_voices.size()


## Plays a UI click from an id or a stream. Unknown ids are ignored.
func play_ui(source: Variant) -> void:
	var stream := _resolve_stream(source, _ui_library)
	if stream == null:
		return
	_play_on(_ui_voices, stream, _ui_cursor)
	_ui_cursor = (_ui_cursor + 1) % _ui_voices.size()


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
	if index < 0 or AudioServer.is_bus_mute(index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


## Registers a stream under an id so scenes can call `play_sfx("id")`.
func register_sfx(id: String, stream: AudioStream) -> void:
	_sfx_library[id] = stream


## Registers a UI click stream under an id.
func register_ui(id: String, stream: AudioStream) -> void:
	_ui_library[id] = stream


func _notification(what: int) -> void:
	if not mute_when_unfocused:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			AudioServer.set_bus_mute(0, true)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			AudioServer.set_bus_mute(0, false)


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


func _resolve_stream(source: Variant, library: Dictionary) -> AudioStream:
	if source is AudioStream:
		return source
	if source is String or source is StringName:
		return library.get(str(source), null)
	return null


func _set_bus_linear(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var value := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null
