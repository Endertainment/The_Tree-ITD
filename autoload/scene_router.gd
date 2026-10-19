extends Node
## Scene transitions: fades out, swaps the scene, fades in.
##
## The fade overlay lives on a CanvasLayer owned by this autoload, so it
## survives the scene swap. Double navigation is ignored. One-shot payloads let
## the battle hand its `RunSummary` to the results screen without a global.

const FADE_SECONDS := 0.2
const OVERLAY_LAYER := 128

var _fade: ColorRect
var _tween: Tween
var _transitioning := false
var _payload: Variant = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.name = "TransitionLayer"
	layer.layer = OVERLAY_LAYER
	add_child(layer)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.04, 0.05, 0.04, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	layer.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Fades to `path`. `force` re-enters the scene that is already loaded.
func goto(path: String, force := false) -> void:
	if _transitioning:
		return
	if not ResourceLoader.exists(path):
		push_error("[SceneRouter] missing scene: %s" % path)
		return
	if not force and _current_scene_path() == path:
		return
	_transitioning = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0)
	Engine.time_scale = 1.0
	# No pooled voice may outlive the scene that started it.
	AudioManager.stop_all_sfx()
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[SceneRouter] change_scene_to_file failed (%d): %s" % [err, path])
		await _fade_to(0.0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_transitioning = false
		return
	await get_tree().process_frame
	await _fade_to(0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false


## Stores `payload` for the next scene, then performs a normal `goto`.
func goto_with_payload(path: String, payload: Variant, force := false) -> void:
	_payload = payload
	await goto(path, force)


## Returns and clears the payload left by the previous scene.
func consume_payload() -> Variant:
	var value: Variant = _payload
	_payload = null
	return value


## True while a transition is in flight.
func is_transitioning() -> bool:
	return _transitioning


func _current_scene_path() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	return scene.scene_file_path


func _fade_to(alpha: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_fade, "modulate:a", alpha, FADE_SECONDS)
	await _tween.finished
